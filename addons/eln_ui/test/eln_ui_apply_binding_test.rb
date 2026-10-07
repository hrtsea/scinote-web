# frozen_string_literal: true

# ELN UI —— 材料类申请单 = 请购单（ADR-0030 / SQ-2026-7783 修复）
#
# 语义（与「领用单」相反，别混）：
#   · 申请时必填「进入哪个库」(repository_id，指 Repository 库)，料还没进库；
#   · 审批通过只**解锁**验收，不碰库存、不做出库；
#   · 到货验收（complete）→ MaterialReceiptPosting 在目标库按名称找/建条目 + 写 Stock →
#     单据置 completed，并把**实际落库的条目 id** 写回 received_repository_row_id；
#   · 出库只由该任务的**原生消耗**发生（任务 stock_consumption → Ledger → ConsumeRecord），
#     详情页据此从 received_repository_row_id 反查溯源。
#
# 旧版「绑定已存在库存条目 + 领用」(repository_row_id) 语义已删除 —— 此文件整体改写为请购。

require_relative 'test_helper'

class ElnUiApplyBindingTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  def setup
    @scene   = build_scene!
    @team    = @scene[:team]
    @project = @scene[:project]
    @creator = @scene[:creator]
  end

  # ---- create_draft：目标库（repository_id）是材料类必填 ----
  def test_material_application_requires_target_repository
    assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError, '材料类不填目标库应被拒') do
      Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
        user: @creator, team: @team, project_id: @project.id, kind: 'material',
        name: '介电磁粉', qty: 10, unit: 'kg', unit_price: 50
      )
    end
  end

  def test_material_application_stores_target_repository_id
    repo = target_repository(team: @team, creator: @creator)
    app = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: '介电磁粉', qty: 10, unit: 'kg', unit_price: 50,
      repository_id: repo.id
    )
    created = Scinote::ElnUi::ResourceApplication.find_by(no: app[:no])
    assert_equal repo.id, created.repository_id, '材料申请单应存下目标库 id'
  end

  def test_material_application_rejects_nonexistent_repository
    assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
      Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
        user: @creator, team: @team, project_id: @project.id, kind: 'material',
        name: 'X', qty: 1, unit: 'kg', unit_price: 1,
        repository_id: 9_999_999
      )
    end
  end

  def test_material_application_rejects_repository_from_other_team
    other_team = ::Team.create!(name: "other-#{SecureRandom.hex(3)}", created_by: @creator)
    other_repo = make_active_repository!(team: other_team, creator: @creator)
    assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError, '绑到别团队的库会把料写进别人库房') do
      Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
        user: @creator, team: @team, project_id: @project.id, kind: 'material',
        name: 'X', qty: 1, unit: 'kg', unit_price: 1,
        repository_id: other_repo.id
      )
    end
  end

  def test_material_application_persists_my_module_id
    repo = target_repository(team: @team, creator: @creator)
    task = build_task_for(@scene)
    app = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: '介电磁粉', qty: 10, unit: 'kg', unit_price: 50,
      repository_id: repo.id, my_module_id: task.id
    )
    created = Scinote::ElnUi::ResourceApplication.find_by(no: app[:no])
    assert_equal task.id, created.my_module_id, '关联任务应被存下'
  end

  # ---- 表单下拉数据源（apply.repositories / apply.myModules）----
  # 前端「目标库 / 关联任务」两个 select 的选项来源就是这两块。
  # 若不下发，前端拿不到选项 → 请购能力形同不存在。
  def test_apply_block_exposes_repositories_for_material
    repo = make_active_repository!(team: @team, creator: @creator, name: '原料库')

    body = Scinote::ElnUi::ResCenterPayload.call(user: @creator, team: @team)
    repos = body[:apply][:repositories]
    refute_empty repos, '材料类「目标库」下拉必须有本团队可读库存'

    target = repos.find { |r| r[:id] == repo.id }
    refute_nil target, '下拉应包含本团队可读库'
    assert_equal '原料库', target[:name]
  end

  def test_apply_block_scopes_repositories_to_current_team
    other_team = ::Team.create!(name: "other-#{SecureRandom.hex(3)}", created_by: @creator)
    other_repo = make_active_repository!(team: other_team, creator: @creator)

    body = Scinote::ElnUi::ResCenterPayload.call(user: @creator, team: @team)
    ids = body[:apply][:repositories].map { |r| r[:id] }
    refute_includes ids, other_repo.id, '别团队的库不得进下拉（等于用表单泄露别人库房清单）'
  end

  def test_apply_block_exposes_my_modules_for_linking
    task = build_task_for(@scene)

    body = Scinote::ElnUi::ResCenterPayload.call(user: @creator, team: @team)
    mods = body[:apply][:myModules]
    refute_empty mods, '材料类「关联任务」下拉必须有本团队可读项目下的任务'

    target = mods.find { |m| m[:id] == task.id }
    refute_nil target, '下拉应包含本团队可读项目下的任务'
    assert_equal @project.name, target[:projectName], '带 projectName 供前端显示归属'
    assert_equal @project.id, target[:projectId]
  end

  # ---- 详情页：item 要回带目标库（不是旧版的 repositoryRowId）----
  def test_detail_items_expose_target_repository
    repo = target_repository(team: @team, creator: @creator)
    app = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: '介电磁粉', qty: 10, unit: 'kg', unit_price: 50,
      repository_id: repo.id
    )
    created = Scinote::ElnUi::ResourceApplication.find_by(no: app[:no])

    payload = Scinote::ElnUi::ResApplyDetailPayload.call(user: @creator, team: @team, no: created.no)
    item = payload[:items].first
    assert_equal repo.id, item[:targetRepositoryId], 'item 应回带目标库 id'
    assert_equal '默认目标库', item[:targetRepositoryName], 'item 应回带目标库名（详情页展示用）'
    assert_nil item[:receivedRepositoryRowId], '入库前 receivedRepositoryRowId 必须为空（条目还不存在）'
  end

  # ---- 入库前：received_repository_row_id 为空 → 溯源为空（正确结果）----
  def test_linked_consumptions_empty_before_receipt
    repo = target_repository(team: @team, creator: @creator)
    app = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: '未入库料', qty: 10, unit: 'kg', unit_price: 50,
      repository_id: repo.id
    )
    created = Scinote::ElnUi::ResourceApplication.find_by(no: app[:no])
    assert_nil created.received_repository_row_id, '前提：尚未入库'

    payload = Scinote::ElnUi::ResApplyDetailPayload.call(user: @creator, team: @team, no: created.no)
    assert_empty payload[:linkedConsumptions], '未入库的申请单不应有任何溯源记录（条目还不存在）'
  end

  # ---- 完整入库链路：到货验收 → 实际条目写回 + Stock 进账 ----
  def test_full_receive_flow_writes_back_row_and_stocks_inventory
    repo = target_repository(team: @team, creator: @creator)
    app = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: '介电磁粉', qty: 200, unit: 'kg', unit_price: 50,
      repository_id: repo.id
    )
    drive_to_received(app[:no])

    created = Scinote::ElnUi::ResourceApplication.find_by(no: app[:no])
    assert_equal 'completed', created.status, '到货验收后单据应为 completed'
    refute_nil created.received_repository_row_id, '入库后必须把实际落库的条目 id 写回'

    # 入库写侧：目标库内长出一条同名条目，库存值 = 申请量
    received = ::RepositoryRow.find(created.received_repository_row_id)
    assert_equal repo.id, received.repository_id, '落库条目应归属目标库'
    assert_equal '介电磁粉', received.name, '落库条目名应取自申请单物料名'

    sv = ::RepositoryStockValue.joins(:repository_cell)
                                .where(repository_cells: { repository_row_id: received.id }).first
    refute_nil sv, '前提：入库应建立库存值'
    assert_equal 200.to_d, sv.amount.to_d, '入库后库存值应等于申请量（请购=加，不是扣）'
  end

  # ---- 入库 + 任务消耗 → 详情页溯源 ----
  def test_linked_consumptions_surfaces_task_consumption_after_receipt
    repo = target_repository(team: @team, creator: @creator)
    task = build_task_for(@scene)
    app = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: '介电磁粉', qty: 200, unit: 'kg', unit_price: 50,
      repository_id: repo.id, my_module_id: task.id
    )
    drive_to_received(app[:no])

    created = Scinote::ElnUi::ResourceApplication.find_by(no: app[:no])
    received = ::RepositoryRow.find(created.received_repository_row_id)

    # 实验消耗：任务消耗该条目 → 原生写 Ledger → decorator 同步 ConsumeRecord
    make_my_module_repository_row!(my_module: task, repository_row: received,
                                   assigned_by: @creator, amount: 10, unit: 'kg')

    ledger = latest_ledger
    refute_nil ledger, '前提：原生消耗链路写了任务消耗流水行'
    refute_nil material_rows(ledger.id).first, '前提：物资消耗明细行已同步登记'

    payload = Scinote::ElnUi::ResApplyDetailPayload.call(user: @creator, team: @team, no: created.no)
    linked = payload[:linkedConsumptions]
    refute_empty linked, '详情页应反查出本单入库条目产生的消耗记录'
    assert linked.any? { |r| r[:name] == '介电磁粉' }, '反查记录应包含介电磁粉消耗行'
  end

  # 🔴 精度：同一条料被两个任务领用是常态，本单只该看到**自己绑定任务**的消耗。
  def test_linked_consumptions_scoped_to_bound_task_not_just_stock_row
    repo = target_repository(team: @team, creator: @creator)
    my_task    = build_task_for(@scene)
    other_task = build_task_for(@scene)

    app = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: '乙醇', qty: 500, unit: 'L', unit_price: 10,
      repository_id: repo.id, my_module_id: my_task.id
    )
    drive_to_received(app[:no])

    created = Scinote::ElnUi::ResourceApplication.find_by(no: app[:no])
    received = ::RepositoryRow.find(created.received_repository_row_id)

    # 别的任务先消耗这条料 —— 不该出现在本单溯源里
    make_my_module_repository_row!(my_module: other_task, repository_row: received,
                                   assigned_by: @creator, amount: 7, unit: 'L')
    payload_before = Scinote::ElnUi::ResApplyDetailPayload.call(
      user: @creator, team: @team, no: created.no
    )
    assert_empty payload_before[:linkedConsumptions],
                 '只有别的任务消耗过 → 本单溯源必须仍为空'

    # 本单绑定任务发生消耗 —— 这时才该出现
    make_my_module_repository_row!(my_module: my_task, repository_row: received,
                                   assigned_by: @creator, amount: 5, unit: 'L')
    payload_after = Scinote::ElnUi::ResApplyDetailPayload.call(
      user: @creator, team: @team, no: created.no
    )
    assert_equal 1, payload_after[:linkedConsumptions].size,
                 '只认绑定任务的这条消耗（不是 2 条）'
    assert_equal '乙醇', payload_after[:linkedConsumptions].first[:name]
  end

  private

  # 驱动一张材料单走完 提交→初审→终审→到货验收入库。
  # 自审放开（2026-10-06）：申请人配为审批人即可审自己的单，故都用 @creator。
  # 走到「已入库」的完整路径。
  # ⚠ ADR-0032：材料类**不再**是终审人点一下就入库 —— 中间必须夹一道到货验收
  #   （申请人交照片+本批数量 → 验货人判通过）。这里补上 make_pending_receipt!，
  #   闸门与「照片必传」等动作规则由 eln_ui_receipt_verification_test.rb 守。
  def drive_to_received(no)
    configure_approver!(user: @creator, project: @project)
    # ⚠ 本 helper 全程用 @creator 一个人走完 submit→初→终→验货，而 @creator 同时是**申请人**。
    #   ADR-0032 D3：自验**默认关闭**（fail-closed），所以这里必须显式打开 ——
    #   这不是「为测试放宽规则」，而是这个场景本来就选了「自审自验」这条路径。
    #   「默认关闭」本身由 eln_ui_receipt_verification_test.rb 单独守。
    Scinote::ElnUi::ReceiptPolicy.set_allow_self_verification!(
      project: @project, value: true, updated_by: @creator
    )
    Scinote::ElnUi::ResourceApplicationWorkflow.call(user: @creator, team: @team, no: no, type: 'submit')
    Scinote::ElnUi::ResourceApplicationWorkflow.call(user: @creator, team: @team, no: no, type: 'approve_group')
    Scinote::ElnUi::ResourceApplicationWorkflow.call(user: @creator, team: @team, no: no, type: 'approve_project')
    app = Scinote::ElnUi::ResourceApplication.find_by(no: no)
    make_pending_receipt!(app: app, created_by: @creator)
    Scinote::ElnUi::ResourceApplicationWorkflow.call(user: @creator, team: @team, no: no, type: 'complete')
  end

  def latest_ledger
    ::RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow').order(id: :desc).first
  end

  def material_rows(ledger_id)
    ::Scinote::ElnUi::ConsumeRecord.where(source_type: 'RepositoryLedgerRecord', source_id: ledger_id)
  end
end
