# frozen_string_literal: true

# ELN UI —— 材料类到货验收（REQ-RES-RECEIPT / ADR-0032）
#
# 守 9 件事（全部落在 spec V1.28 `SCN-RES-RECEIPT-1~4` 与被改写的
# `SCN-RES-APPROVE-3` / `SCN-RES-APPROVER-5` 上，别在别处打折）：
#   1. **照片是入库的前置证据**（-1）：没照片连「待验」都不成立；
#   2. **本批数量由验货人申报**（-3）：qty 必填且 > 0；入库按它写，不按整单量；
#   3. **分批收口**（-3）：累计已验 < 申请量 ⇒ 留在「已终审通过」；≥ ⇒ completed；
#   4. **验货人是独立阶段**（-2）：未配 `receipt` 名单 ⇒ **无人可验**（fail-closed），
#      **不**回退到终审名单（那是 ADR-0030 被修正掉的那条）；
#   5. **自验按项目开关**（-2）：默认关闭；开启才允许验自己的单；
#   6. **判不通过退回待审批**（`SCN-RES-APPROVE-3`）：状态回 submitted、记录与照片**保留**、
#      理由必填；补货后可再提交新一轮（历史轮次不清）；
#   7. **未验货积压冻结新建材料申请**（-4）：阈值来自模块级配置（默认 2、可配），
#      **服务类不受影响**（与 `SCN-RES-TEST-STRIKE-2` 镜像互补）；
#   8. **豁免放行一次**且**不消解未验货事实**（-4，委托 ServiceStrikeBook 同一张表）；
#   9. **材料/服务各走各的闸门**：服务类 complete 仍由终审人执行，不经过货
#      （V1.21 / SCN-RES-APPROVE-4；把验货闸门提到分支外会让服务永远完不成 —— 实测踩过）。
#
# ⚠ 两条容易写成「假绿」的陷阱，本文件刻意避开：
#   · 断言**收口**时必须造**分批**场景（只验一次就 completed 测不出「累计达标」这个规则）；
#   · 断言**阻断**时必须先确认计数口径是「未验货申请数」而不是「批次数」。

require_relative 'test_helper'

class ElnUiReceiptVerificationTest < AcTest::Base
  include ElnUiFactories

  WF   = Scinote::ElnUi::ResourceApplicationWorkflow
  BOOK = Scinote::ElnUi::ReceiptPendingBook
  RV   = Scinote::ElnUi::ReceiptVerification
  P    = Scinote::ElnUi::ResourceApprovalPolicy

  def setup
    @scene   = build_scene!
    @team    = @scene[:team]
    @project = @scene[:project]
    @creator = @scene[:creator]
    @repo    = target_repository(team: @team, creator: @creator)
    @verifier = begin
      u = make_user!(name: 'inspector')
      join_team!(u, @team)
      u
    end
  end

  # ---- 场景助手 ----

  def configure_block_limit!(n)
    AddonSetting.update_for('eln_ui', enabled: true, configuration: { 'receipt_pending_block_limit' => n })
  end

  # 造一张已终审通过、等待验货的材料申请单
  def make_ready_app!(qty: 10, name: '介电磁粉')
    res = WF.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: name, qty: qty, unit: 'kg', unit_price: 50, repository_id: @repo.id
    )
    app = Scinote::ElnUi::ResourceApplication.find_by!(no: res[:no])
    configure_approver!(user: @verifier, project: @project)   # 含 receipt 阶段
    wf!(app.requestor, app, 'submit')
    wf!(@verifier, app, 'approve_group')
    wf!(@verifier, app, 'approve_project')
    app.reload
  end

  def wf!(user, app, type, **kw)
    WF.call(user: user, team: app.project.team, no: app.no, type: type, **kw)
  end

  # 提交验收的载荷走 `receipt:`（见 ResourceApplicationWorkflow.call 的注释：
  # 动作专属数据不塞进共享基类的 kwargs）
  def submit_receipt!(app, qty:, photos: 1, user: nil)
    wf!(user || @creator, app, 'submit_receipt',
        receipt: { qty: qty, photos: Array.new(photos) { fake_photo } })
  end

  def stock_amount!(app)
    row = RepositoryRow.find_by!(id: app.reload.received_repository_row_id)
    row.repository_stock_value.amount.to_d
  end

  # ============================================================
  # 1. 照片是入库的前置证据（SCN-RES-RECEIPT-1）
  # ============================================================

  def test_receipt_requires_at_least_one_photo
    app = make_ready_app!
    err = assert_raises(WF::WorkflowError) do
      wf!(@creator, app, 'submit_receipt', receipt: { qty: 10, photos: [] })
    end
    assert_match(/照片/, err.message)
    assert_equal 0, RV.for_application(app).count, '没照片就不该产生验收记录'
  end

  def test_receipt_with_photo_creates_pending_record
    app = make_ready_app!
    submit_receipt!(app, qty: 10)
    v = RV.for_application(app).first
    assert v, '应产生一条验收记录'
    assert v.pending?
    assert_equal 10.to_d, v.qty
    assert_equal 1, v.photos.count, '照片应挂在验收记录上'
  end

  # ============================================================
  # 2. 本批数量（SCN-RES-RECEIPT-3）
  # ============================================================

  def test_only_requestor_can_submit_receipt
    app = make_ready_app!
    err = assert_raises(WF::WorkflowError) { submit_receipt!(app, qty: 10, user: @verifier) }
    assert_match(/申请人本人/, err.message)
  end

  def test_receipt_rejects_non_positive_qty
    app = make_ready_app!
    err = assert_raises(WF::WorkflowError) { submit_receipt!(app, qty: 0) }
    assert_match(/数量/, err.message)
    assert_equal 0, RV.for_application(app).count, '数量非法不该留下记录'
  end

  def test_batch_qty_is_what_gets_posted_not_whole_order
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 4, created_by: @creator)
    wf!(@verifier, app, 'complete')
    assert_equal 4.to_d, stock_amount!(app), '入库数量应取本批 4kg，而不是整单 10kg'
  end

  # ============================================================
  # 3. 分批收口（SCN-RES-RECEIPT-3）
  # ============================================================

  def test_partial_batch_keeps_application_open
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 4, created_by: @creator)
    wf!(@verifier, app, 'complete')
    assert_equal 'project_approved', app.reload.status, '累计 4 < 10，应留在待验货态'
    assert_nil app.completed_at
  end

  def test_second_batch_closes_application
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 4, created_by: @creator)
    wf!(@verifier, app, 'complete')
    make_pending_receipt!(app: app, qty: 6, created_by: @creator)
    wf!(@verifier, app, 'complete')
    assert_equal 'completed', app.reload.status, '累计 4+6 ≥ 10 应收口'
    assert_equal 10.to_d, stock_amount!(app)
  end

  def test_pending_record_blocks_second_submission
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 4, created_by: @creator)
    err = assert_raises(WF::WorkflowError) { submit_receipt!(app, qty: 6) }
    assert_match(/待验货/, err.message)
  end

  # ============================================================
  # 4. 验货人是独立阶段，未配即 fail-closed（SCN-RES-RECEIPT-2）
  # ============================================================

  def test_complete_blocked_when_receipt_stage_unconfigured
    app = make_ready_app!(qty: 10)
    clear_approvers!(@project)                      # 一条名单都不留
    make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    err = assert_raises(WF::WorkflowError) { wf!(@verifier, app, 'complete') }
    assert_match(/验货人名单/, err.message, '未配 receipt 名单必须 fail-closed')
  end

  def test_final_approver_cannot_verify_when_not_in_receipt_stage
    # 只配终审阶段，不配 receipt —— 终审人**不能**验货（这正是 ADR-0032 修正的那条）
    app = make_ready_app!(qty: 10)
    clear_approvers!(@project)
    configure_approver!(user: @verifier, project: @project, stages: %w[group project])
    make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    assert_raises(WF::WorkflowError) { wf!(@verifier, app, 'complete') }
  end

  # ============================================================
  # 5. 自验按项目开关（SCN-RES-RECEIPT-2）
  # ============================================================

  def test_self_verification_denied_by_default
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    # @creator 是申请人；只把他配进 receipt 名单，自验开关仍是关的
    Scinote::ElnUi::ProjectApprover.add!(project: @project, user: @creator, stage: 'receipt')
    err = assert_raises(WF::WorkflowError) { wf!(@creator, app, 'complete') }
    assert_match(/不允许自验|验货人名单/, err.message)
  end

  def test_self_verification_allowed_when_project_enables_it
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    Scinote::ElnUi::ProjectApprover.add!(project: @project, user: @creator, stage: 'receipt')
    Scinote::ElnUi::ReceiptPolicy.set_allow_self_verification!(project: @project, value: true, updated_by: @creator)
    wf!(@creator, app, 'complete')
    assert_equal 'completed', app.reload.status
  end

  def test_non_requestor_in_receipt_stage_can_verify
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    wf!(@verifier, app, 'complete')   # @verifier 不是申请人，不需要开自验
    assert_equal 'completed', app.reload.status
  end

  # ============================================================
  # 6. 判不通过 → 退回待审批，记录保留（SCN-RES-APPROVE-3）
  # ============================================================

  def test_reject_requires_reason
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    err = assert_raises(WF::WorkflowError) { wf!(@verifier, app, 'reject_receipt', reason: '  ') }
    assert_match(/理由/, err.message)
  end

  def test_reject_returns_to_submitted_and_keeps_record
    app = make_ready_app!(qty: 10)
    v = make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    wf!(@verifier, app, 'reject_receipt', reason: '外包装破损')
    assert_equal 'submitted', app.reload.status, '判不通过应退回待审批，重走两级审批'
    v.reload
    assert_equal 'rejected', v.status
    assert_equal '外包装破损', v.rejection_reason
    assert_equal 1, v.photos.count, '照片必须保留（审计留痕）'
    assert_nil app.reload.received_repository_row_id, '未通过不该写库存'
  end

  def test_receipt_history_accumulates_across_rounds
    app = make_ready_app!(qty: 10)
    v1 = make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    wf!(@verifier, app, 'reject_receipt', reason: '少一箱')
    # ⚠ 退回的是 **submitted**（不是 draft）：所以**不需要**再 submit ——
    #   apply_submit 只接受 draft，而 apply_approve_group 接受 submitted。
    #   申请人补完货直接由小组组长重走初审 → 终审 → 验货。
    wf!(@verifier, app, 'approve_group')
    wf!(@verifier, app, 'approve_project')
    v2 = make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    assert_equal 2, RV.for_application(app).count, '两轮验收记录都该留着'
    refute_equal v1.id, v2.id
    assert_equal 'rejected', v1.reload.status
    assert v2.pending?
  end

  # 已知限制（写进用例而不是留成口头约定）：退回 submitted 后申请人**不能改申请量**
  # （编辑只允许 draft）。补货不改总量时无所谓；要改量就得先人工把单子退回草稿。
  def test_rejected_application_is_not_editable_but_can_be_reapproved
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    wf!(@verifier, app, 'reject_receipt', reason: '外箱破损')
    assert_equal 'submitted', app.reload.status
    assert_raises(WF::WorkflowError) { wf!(@creator, app, 'submit') }  # submitted 不能重复 submit
    wf!(@verifier, app, 'approve_group')                                  # 但能重走审批
    assert_equal 'group_approved', app.reload.status
  end

  # ============================================================
  # 7 + 8. 未验货积压冻结（SCN-RES-RECEIPT-4），与 strike 镜像
  # ============================================================

  def new_material_draft!
    WF.create_draft(
      user: @creator, team: @team, project_id: @project.id, kind: 'material',
      name: '新料', qty: 1, unit: 'kg', unit_price: 10, repository_id: @repo.id
    )
  end

  def test_no_block_below_threshold
    configure_block_limit!(2)
    make_ready_app!(qty: 10)                 # 1 张未验货
    assert_equal 1, BOOK.for_applicant(@creator.id).size
    new_material_draft!                      # 1 < 2 ⇒ 不拦（建单成功本身就是断言）
    assert BOOK.frozen?(@creator.id) == false
  end

  def test_blocks_material_draft_at_threshold
    configure_block_limit!(2)
    2.times { |i| make_ready_app!(qty: 10, name: "料#{i}") }
    assert_equal 2, BOOK.for_applicant(@creator.id).size
    err = assert_raises(WF::WorkflowError) { new_material_draft! }
    assert_match(/尚未验货入库/, err.message)
    assert_match(/阈值/, err.message)
  end

  def test_service_draft_not_blocked_by_material_pending
    configure_block_limit!(1)
    make_ready_app!(qty: 10)
    catalog = make_service_catalog!(name: 'DSC 差示扫描量热')
    # 服务类不受「材料未验货」冻结影响（镜像：服务侧只被「逾期未回填」冻）
    WF.create_draft(user: @creator, team: @team, project_id: @project.id, kind: 'service',
                    name: catalog.name, qty: 1, unit: '次', service_catalog_id: catalog.id)
  end

  def test_waiver_releases_once_and_does_not_clear_debt
    configure_block_limit!(1)
    app = make_ready_app!(qty: 10)
    Scinote::ElnUi::ServiceStrikeBook.grant_waiver!(user: @creator, granted_by: @verifier, reason: '紧急')
    new_material_draft!   # 豁免放行这一次
    assert_raises(WF::WorkflowError, '豁免用后即失效，第二次应再被拦') { new_material_draft! }
    assert_equal 1, BOOK.for_applicant(@creator.id).size, '豁免不消解未验货事实'
  end

  def test_completed_application_is_not_counted_as_pending
    configure_block_limit!(1)
    app = make_ready_app!(qty: 10)
    make_pending_receipt!(app: app, qty: 10, created_by: @creator)
    wf!(@verifier, app, 'complete')
    assert_equal 0, BOOK.for_applicant(@creator.id).size, '已收口的单不再算未验货'
    new_material_draft!  # 不拦
  end

  # 🔴 回归（2026-10-06 真机实测踩到）：服务类申请**永远不经历货**，它停在
  #   `project_approved` 是「等执行」，不是「等验货」。若把它算进未验货名额，
  #   攒够阈值就会把新建材料申请误冻 —— 生产 seed 的 `SQ-2026-0092`
  #   （服务、project_approved）曾让 unverified_count 凭空 +1。
  def test_service_application_is_never_counted_as_unverified
    configure_block_limit!(1)
    catalog = make_service_catalog!(name: 'DSC 差示扫描量热')
    res = WF.create_draft(user: @creator, team: @team, project_id: @project.id, kind: 'service',
                          name: catalog.name, qty: 2, unit: '次', service_catalog_id: catalog.id)
    svc = Scinote::ElnUi::ResourceApplication.find_by!(no: res[:no])
    configure_approver!(user: @verifier, project: @project, stages: %w[group project])
    wf!(@creator, svc, 'submit')
    wf!(@verifier, svc, 'approve_group')
    wf!(@verifier, svc, 'approve_project')
    svc.reload
    assert_equal 'project_approved', svc.status
    assert_equal 0, BOOK.for_applicant(@creator.id).size,
                 '服务类不经历货，不得占用「未验货」名额'
    new_material_draft!  # 阈值 1 但计数 0 ⇒ 不拦
  end

  def test_block_reason_is_nil_when_not_frozen
    assert_nil BOOK.block_reason(@creator.id)
  end

  # ============================================================
  # 9. 服务类仍由终审人完成（不进到货验收）
  # ============================================================

  def test_service_complete_still_by_final_approver
    configure_block_limit!(99)
    catalog = make_service_catalog!(name: 'DSC 差示扫描量热')
    res = WF.create_draft(user: @creator, team: @team, project_id: @project.id, kind: 'service',
                          name: catalog.name, qty: 1, unit: '次', service_catalog_id: catalog.id)
    app = Scinote::ElnUi::ResourceApplication.find_by!(no: res[:no])
    configure_approver!(user: @verifier, project: @project, stages: %w[group project]) # 不给 receipt
    wf!(@creator, app, 'submit')
    wf!(@verifier, app, 'approve_group')
    wf!(@verifier, app, 'approve_project')
    wf!(@verifier, app, 'complete')   # 不需要待验记录
    assert_equal 'completed', app.reload.status
  end

  # ============================================================

  private

  def fake_photo
    { io: StringIO.new('fake-jpeg'), filename: 'receipt.jpg', content_type: 'image/jpeg' }
  end
end
