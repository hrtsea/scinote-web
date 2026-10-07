# frozen_string_literal: true
#
# ELN UI —— 测试表征服务档案 + 服务行登记链路（REQ-RES-TEST / REQ-RES-ARCHIVE）
#
# 守 4 件事：
#   1. 服务档案是服务行的**唯一**单价来源（spec V1.21 L986 / L1051）：
#      申请创建时强制绑档案，表单手填单价被档案覆盖；登记时只取档案快照；
#   2. 服务行在**执行完成**（申请单 complete）这一刻登记，不是终审通过
#      （SCN-RES-TEST-1「当一次测试实际执行完成，则登记一行服务执行行」）；
#   3. 需验收 → 登记即「待验收」不计花费；不需验收 → 登记即计入（spec L1010）；
#   4. fail-closed：没绑档案的服务单不许落行，宁可 422 也不静默按 ¥0 记一笔。

require_relative 'test_helper'

class ElnUiServiceCatalogTest < AcTest::Base
  include ElnUiFactories

  WF = Scinote::ElnUi::ResourceApplicationWorkflow

  # 走一遍二段式审批到「终审通过」（终审通过＝获准执行，还没登记）
  # ⚠ submit 的闸门是「申请人本人」，初审/终审/完成才是「同队非本人」——
  #   别拿 mate 去 submit，会直接被 gate! 挡回来。
  # ⚠2026-10-05 起审批是**显式名单**（REQ-RES-APPROVER，fail-closed）：
  #   mate 要能初审/终审，必须先住在名单里 —— 「同队非本人」那条老口径已经废了。
  def approve_project!(app:, mate:)
    configure_approver!(user: mate, project: app.project)
    WF.call(user: app.requestor, team: app.project.team, no: app.no, type: 'submit') if app.draft?
    WF.call(user: mate, team: app.project.team, no: app.no, type: 'approve_group')
    WF.call(user: mate, team: app.project.team, no: app.no, type: 'approve_project')
  end

  # ⚠ ADR-0032：**材料类**complete 前必须先有「待验」验收记录（照片 + 本批数量）；
  #   服务类不经过货（不建库存），仍由终审人直接完成 —— 两条路径的闸门不同，别混。
  def complete!(app:, mate:)
    make_pending_receipt!(app: app, created_by: app.requestor) if app.material?
    WF.call(user: mate, team: app.project.team, no: app.no, type: 'complete')
  end

  def make_reviewer!(scene)
    user = make_user!(name: 'reviewer')
    join_team!(user, scene[:team])
    user
  end

  def draft_service_app!(scene:, catalog:, qty: '3', typed_price: 999)
    result = WF.create_draft(
      user: scene[:creator], team: scene[:team],
      project_id: scene[:project].id, kind: 'service',
      name: catalog.name, qty: qty, unit: '次', unit_price: typed_price,
      service_catalog_id: catalog.id
    )
    # 编号由 service 生成（SQ-YYYY-NNNN），回查按 no 拿单据
    Scinote::ElnUi::ResourceApplication.find_by!(no: result[:no])
  end

  # ------------------------------------------------------------
  # ① 服务档案本体
  # ------------------------------------------------------------

  # spec L1010「requires_acceptance … 默认开启＝需验收」—— 默认值落在列上，
  # 代码里不许再兜一层「默认 true」。
  def test_service_catalog_defaults_to_requires_acceptance
    catalog = make_service_catalog!(name: '万能试验机拉伸')

    assert_equal true, catalog.reload.requires_acceptance,
                 '新建档案条目默认需验收（spec L1010）'
    assert_equal true, catalog.acceptance_required?
  end

  def test_catalog_carries_period_and_vendor
    catalog = make_service_catalog!(name: 'XRF 元素分析', unit_price: 350.5,
                                    requires_acceptance: false, cycle_days: 7, vendor: '中检院')

    assert_equal '中检院', catalog.vendor
    assert_equal 7, catalog.cycle_days
    assert_equal 350.5.to_d, catalog.snapshot_price
    assert_equal false, catalog.acceptance_required?, '显式关掉 → 登记即计入花费'
  end

  # ------------------------------------------------------------
  # ② 申请：档案是单价唯一来源
  # ------------------------------------------------------------

  # 负例：服务类不绑档案 → 拒绝，且**不落单**（否则后面登记时只能 fail-open 兜 ¥0）
  def test_create_draft_service_requires_catalog
    scene = build_scene!

    e = assert_raises(WF::WorkflowError) do
      WF.create_draft(user: scene[:creator], team: scene[:team],
                      project_id: scene[:project].id, kind: 'service',
                      name: 'DSC', qty: '2', unit: '次', service_catalog_id: nil)
    end
    assert_match(/服务档案/, e.message)
    assert_equal 0, Scinote::ElnUi::ResourceApplication.where(project_id: scene[:project].id).count,
                   '校验失败不得落行'
  end

  # 负例：档案 id 根本不存在（表单伪造）→ 同样拒
  def test_create_draft_service_rejects_unknown_catalog
    scene = build_scene!

    assert_raises(WF::WorkflowError) do
      WF.create_draft(user: scene[:creator], team: scene[:team],
                      project_id: scene[:project].id, kind: 'service',
                      name: 'DSC', qty: '2', unit: '次', service_catalog_id: 999_999)
    end
    assert_equal 0, Scinote::ElnUi::ResourceApplication.count
  end

  # 表单手填单价在材料上是可填的；服务上一律被档案快照覆盖 ——
  # 留一条手填路，花费行就再也说不清这个 ¥N 从哪来。
  def test_create_draft_service_price_comes_from_catalog_not_form
    scene = build_scene!
    catalog = make_service_catalog!(name: 'DSC 差示扫描量热', unit_price: 1200,
                                    requires_acceptance: true)

    no = WF.create_draft(user: scene[:creator], team: scene[:team],
                         project_id: scene[:project].id, kind: 'service',
                         name: catalog.name, qty: '3', unit: '次',
                         unit_price: 999, service_catalog_id: catalog.id)[:no]
    app = Scinote::ElnUi::ResourceApplication.find_by(no: no)

    assert_equal 1200, app.item_list.first[:unit_price],
                 '服务单价 = 档案快照，表单填的 999 不生效'
    assert_equal '次', app.item_list.first[:unit], '服务行单位固定「次」'
  end

  # ------------------------------------------------------------
  # ③ 登记：执行完成（complete）这一刻
  # ------------------------------------------------------------

  # 主链路：终审通过**不**登记，complete（服务已执行）才落一行服务执行行
  def test_complete_registers_service_row_on_execution_completion
    scene = build_scene!
    catalog = make_service_catalog!(name: 'DSC 差示扫描量热', unit_price: 1200,
                                    requires_acceptance: true)
    app = draft_service_app!(scene: scene, catalog: catalog, qty: '3')
    mate = make_reviewer!(scene)

    approve_project!(app: app, mate: mate)
    assert_equal 0, Scinote::ElnUi::ConsumeRecord.where(kind: 'service').count,
                   '终审通过只「获准执行」，不得登记（SCN-RES-TEST-1）'

    complete!(app: app, mate: mate)

    assert_equal 'completed', app.reload.status
    rows = Scinote::ElnUi::ConsumeRecord.where(source_id: app.id).to_a
    assert_equal 1, rows.size, '完成才登记一行服务执行行'
    row = rows.first
    assert_equal 'service', row.kind
    assert_equal catalog.name, row.name
    assert_equal 3, row.quantity.to_i, '登记数量 = 审批通过时提交的服务次数'
    assert_equal '次', row.unit
    assert_equal 1200, row.unit_price.to_i, '单价 = 档案快照'
    assert_equal 3600, row.amount.to_i, '金额 = 次数 × 单价'
    assert_equal 'pending_acceptance', row.result_status, '需验收 → 待验收'
    assert_equal false, row.costable?, '待验收的服务行不计花费（spec L109）'
    assert_equal scene[:project].id, row.project_id
    assert_equal scene[:creator].id, row.user_id, '操作人 = 申请人（谁消费这笔服务）'
  end

  # spec L1010：不需验收的条目，登记即计入花费
  def test_service_row_settled_when_acceptance_off_counts_as_cost
    scene = build_scene!
    catalog = make_service_catalog!(name: '场地洁净度检测', unit_price: 200,
                                    requires_acceptance: false)
    app = draft_service_app!(scene: scene, catalog: catalog, qty: '2')
    mate = make_reviewer!(scene)

    approve_project!(app: app, mate: mate)
    complete!(app: app, mate: mate)

    row = Scinote::ElnUi::ConsumeRecord.find_by(source_id: app.id)
    assert_equal 'settled', row.result_status, '不需验收 → 登记即计入'
    assert_equal true, row.costable?
    assert_equal 400, row.amount.to_i
  end

  # 「快照」两个字的含义：登记后改档案价，老行的花费不动
  def test_service_row_amount_is_frozen_snapshot_after_registration
    scene = build_scene!
    catalog = make_service_catalog!(name: 'DSC 差示扫描量热', unit_price: 1200)
    app = draft_service_app!(scene: scene, catalog: catalog, qty: '2')
    mate = make_reviewer!(scene)

    approve_project!(app: app, mate: mate)
    complete!(app: app, mate: mate)

    catalog.update!(unit_price: 5000)
    row = Scinote::ElnUi::ConsumeRecord.find_by(source_id: app.id)

    assert_equal 1200, row.reload.unit_price.to_i, '快照：档案改价不回溯'
    assert_equal 2400, row.amount.to_i
  end

  # 幂等：重复登记（同一 source）只刷新那一行，不产第二行
  # —— 唯一索引 idx_eln_ui_consumerec_on_source 是硬闸门，这里是行为层面的确认。
  def test_service_row_registration_is_idempotent
    scene = build_scene!
    catalog = make_service_catalog!(name: 'DSC', unit_price: 800)
    app = draft_service_app!(scene: scene, catalog: catalog, qty: '1')
    mate = make_reviewer!(scene)

    approve_project!(app: app, mate: mate)
    complete!(app: app, mate: mate)

    Scinote::ElnUi::ConsumeRecord.sync_service_from_application!(
      app: app.reload, occurred_at: app.completed_at
    )
    Scinote::ElnUi::ConsumeRecord.sync_service_from_application!(
      app: app.reload, occurred_at: app.completed_at
    )

    assert_equal 1, Scinote::ElnUi::ConsumeRecord.where(source_id: app.id).count
  end

  # 材料类走 Ledger 侧登记，complete 不重复记
  def test_complete_material_registers_no_service_row
    scene = build_scene!
    created = WF.create_draft(user: scene[:creator], team: scene[:team],
                              project_id: scene[:project].id, kind: 'material',
                              name: 'PP 基料 K8003', qty: '20', unit: 'kg',
                              unit_price: 350,
                              repository_id: target_repository_id(team: scene[:team], creator: scene[:creator]))
    app = Scinote::ElnUi::ResourceApplication.find_by(no: created[:no])
    mate = make_reviewer!(scene)

    approve_project!(app: app, mate: mate)
    complete!(app: app, mate: mate)

    assert_equal 'completed', app.reload.status
    assert_equal 0, Scinote::ElnUi::ConsumeRecord.where(source_id: app.id).count,
                   '材料行的登记在 Ledger 侧（sync_material_from_ledger!），这里不重复记'
  end

  # ------------------------------------------------------------
  # ④ fail-closed：没绑档案的服务单，宁可 422 也不静默记 ¥0
  # ------------------------------------------------------------

  def test_complete_service_without_catalog_raises_and_rolls_back
    scene = build_scene!
    catalog = make_service_catalog!(name: 'DSC', unit_price: 1200)
    app = draft_service_app!(scene: scene, catalog: catalog, qty: '2')
    mate = make_reviewer!(scene)

    approve_project!(app: app, mate: mate)
    # 模拟「档案事后被删 / items 里绑定被摘掉」：登记时没有单价来源
    app.update!(items: [{ 'kind' => 'service', 'name' => 'DSC',
                          'qty' => 2, 'unit' => '次', 'unit_price' => 1200 }])

    e = assert_raises(WF::WorkflowError) do
      complete!(app: app, mate: mate)
    end
    assert_match(/服务档案/, e.message)

    assert_equal 'project_approved', app.reload.status,
                 '写侧抛错 → 事务回滚，状态不能被带成 completed'
    # ⚠ 不许静默按 ¥0 落一行：那会在花费页签上留一条「¥0 测试服务」，
    #   账面看着平，实际口径是坏的（假绿）。
    assert_equal 0, Scinote::ElnUi::ConsumeRecord.where(source_id: app.id).count
  end

  # ------------------------------------------------------------
  # ⑤ payload：档案要能被申请表单的下拉读到，并带上「是否需验收」
  # ------------------------------------------------------------

  # spec SCN-RES-TEST-4：列表必须呈现每个条目的「是否需验收」配置，
  # 使「为何尚未计入花费」可被解释 —— 所以只下发 id + 名字是不够的。
  def test_res_center_payload_lists_service_catalogs_with_acceptance_flag
    scene = build_scene!
    make_service_catalog!(name: 'DSC 差示扫描量热', unit_price: 1200, requires_acceptance: true)
    make_service_catalog!(name: '场地洁净度检测', unit_price: 200, requires_acceptance: false)

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: scene[:team])
    list = body[:apply][:serviceCatalogs]

    assert_equal 2, list.size
    assert_equal ['DSC 差示扫描量热', '场地洁净度检测'].sort, list.map { |c| c[:name] }.sort
    assert_equal true, list.find { |c| c[:name] == 'DSC 差示扫描量热' }[:requiresAcceptance]
    assert_equal false, list.find { |c| c[:name] == '场地洁净度检测' }[:requiresAcceptance]
    assert_equal 1200, list.find { |c| c[:name] == 'DSC 差示扫描量热' }[:unitPrice]
  end

  def test_res_center_service_catalogs_is_empty_when_no_catalog
    scene = build_scene!

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal [], body[:apply][:serviceCatalogs],
                   '一个档案都没有 → 显式空集，不回落演示值'
  end
end
