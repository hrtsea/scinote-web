# frozen_string_literal: true

# ELN UI —— 资源申请审批人配置（REQ-RES-APPROVER · ADR-0029）
#
# 守 6 件事（fail-closed + 可见范围并集 + 审批判定单一路径 + 配置权限 + 一键初始化 + 自审放开）：
#   1. ResourceApprovalPolicy.can_approve? —— 名单是唯一口径；未配置即 false（fail-closed）
#   2. visible_applications —— 本人 ∪ 项目负责人 ∪ 配置审批人（三集合并集）
#   3. project_owner? —— 双轨（supervised_by OR Project 级 UA owner role）
#   4. can_configure? / configurable_projects —— 仅项目负责人；团队/单位管理员无万能位
#   5. ProjectApproversPayload + ProjectApproversController —— 面板数据 / GET/POST/DELETE/init
#   6. 自审放开（2026-10-06 用户指令）：申请人配为审批人后即可审自己的单。
#
# ⚠ 前面板口径：「自己批自己」过去是硬拦截，现已取消；`can_approve?` 只对 team 与名单校验。

require_relative 'test_helper'

class ElnUiApproverTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  def setup
    @scene   = build_scene!
    @team    = @scene[:team]
    @project = @scene[:project]
    @creator = @scene[:creator]
    @owner   = make_user!(name: '项目负责人')
    join_team!(@owner, @team)
    make_project_owner!(@project, user: @owner)
  end

  # ============================================================
  # 1. can_approve?（fail-closed + 名单唯一口径 + 自审放开）
  # ============================================================

  # 未配置任何审批人 → 谁都批不了（fail-closed）
  def test_can_approve_false_when_no_approvers_configured
    app = make_resource_application!(project: @project, requestor: @creator,
                                     no: 'SQ-2026-1001', status: 'submitted')
    mate = make_approver_user! # 在 team 但不在名单

    refute can_approve?(mate, app, 'group'), '未配置审批人 → fail-closed，无人可批'
  end

  # 配进名单且非本人 → 可批
  def test_can_approve_true_when_configured_and_not_requestor
    app = make_resource_application!(project: @project, requestor: @creator,
                                     no: 'SQ-2026-1002', status: 'submitted')
    mate = make_approver_user!(project: @project)

    assert can_approve?(mate, app, 'group')
  end

  # 自审：申请人配为审批人即可审自己的单（2026-10-06 放开）
  def test_can_approve_true_for_requestor_when_configured
    app = make_resource_application!(project: @project, requestor: @creator,
                                     no: 'SQ-2026-1003', status: 'submitted')
    configure_approver!(user: @creator, project: @project)

    assert can_approve?(@creator, app, 'group'), '自审：申请人配为审批人即可审自己的单'
  end

  # 跨团队一律 false（名单对、但不在同团队）
  def test_can_approve_false_across_team
    other_user = make_user!
    other_team = ::Team.create!(name: "t2-#{SecureRandom.hex(3)}", created_by: other_user)
    other_proj = make_project!(team: other_team, creator: other_user)
    configure_approver!(user: @creator, project: other_proj)
    app = make_resource_application!(project: other_proj, requestor: other_user,
                                     no: 'SQ-2026-1004', status: 'submitted')

    refute can_approve?(@creator, app, 'group', team: @team), '跨团队：即便在名单内也一律 false'
  end

  # ============================================================
  # 2. visible_applications（本人 ∪ 负责人 ∪ 审批人）
  # ============================================================

  # 普通组员：只看得见自己提交的
  def test_visible_scope_self_for_plain_member
    member = make_approver_user!
    app_other = make_resource_application!(project: @project, requestor: @creator,
                                           no: 'SQ-2026-1010', status: 'submitted')
    app_self = make_resource_application!(project: @project, requestor: member,
                                          no: 'SQ-2026-1011', status: 'submitted')

    ids = Scinote::ElnUi::ResourceApprovalPolicy.visible_applications(user: member, team: @team).pluck(:id)
    assert_includes ids, app_self.id
    refute_includes ids, app_other.id, '普通组员只看本人提交（即便同项目）'
  end

  # 项目负责人：看得到项目下全部（含他人草稿）
  def test_visible_scope_manage_for_owner
    app_other = make_resource_application!(project: @project, requestor: @creator,
                                           no: 'SQ-2026-1012', status: 'draft')

    ids = Scinote::ElnUi::ResourceApprovalPolicy.visible_applications(user: @owner, team: @team).pluck(:id)
    assert_includes ids, app_other.id, '负责人看得到项目下全部申请（含草稿）'
  end

  # 被指名审批人：看得到对应项目的全部（即便不是负责人也不是申请人）
  def test_visible_scope_manage_for_named_approver
    approver = make_approver_user!
    configure_approver!(user: approver, project: @project)
    app_other = make_resource_application!(project: @project, requestor: @creator,
                                           no: 'SQ-2026-1013', status: 'submitted')

    ids = Scinote::ElnUi::ResourceApprovalPolicy.visible_applications(user: approver, team: @team).pluck(:id)
    assert_includes ids, app_other.id, '指名审批人看得到该项目全部申请'
    assert_equal 'manage', Scinote::ElnUi::ResourceApprovalPolicy.visible_scope(approver, @team)
  end

  # ============================================================
  # 3. project_owner?（双轨）
  # ============================================================

  def test_project_owner_true_for_owner
    assert Scinote::ElnUi::ResourceApprovalPolicy.project_owner?(@owner, @project)
  end

  def test_project_owner_false_for_plain_member
    member = make_approver_user!
    refute Scinote::ElnUi::ResourceApprovalPolicy.project_owner?(member, @project)
  end

  # ============================================================
  # 4. can_configure?（无万能位）
  # ============================================================

  def test_can_configure_true_for_owner
    assert Scinote::ElnUi::ResourceApprovalPolicy.can_configure?(@owner, @project, @team)
  end

  def test_can_configure_false_for_non_owner_member
    member = make_approver_user!
    refute Scinote::ElnUi::ResourceApprovalPolicy.can_configure?(member, @project, @team)
  end

  # 团队管理员若不是项目负责人，仍无权配置（Q5-2 不开万能位）
  def test_can_configure_false_for_team_admin_not_owner
    admin = make_approver_user!
    role = ::UserRole.find_predefined_team_admin_role if ::UserRole.respond_to?(:find_predefined_team_admin_role)
    role ||= ::UserRole.where(name: %w[admin team_admin]).first
    if role
      ::UserAssignment.find_or_initialize_by(user: admin, assignable: @team, team_id: @team.id).tap do |ua|
        ua.user_role = role
        ua.assigned = :manually
        ua.save!
      end
    end
    refute Scinote::ElnUi::ResourceApprovalPolicy.can_configure?(admin, @project, @team),
           '团队管理员若非项目负责人，仍无权配置审批人（Q5-2 不开万能位）'
  end

  # ============================================================
  # 5. unconfigured_stages / available_actions
  # ============================================================

  def test_unconfigured_stages_lists_empty_stages
    clear_approvers!(@project)
    assert_equal %w[group project receipt], Scinote::ElnUi::ResourceApprovalPolicy.unconfigured_stages(@project)
  end

  def test_available_actions_for_named_approver
    app = make_resource_application!(project: @project, requestor: @creator,
                                     no: 'SQ-2026-1020', status: 'submitted')
    configure_approver!(user: @owner, project: @project)
    actions = Scinote::ElnUi::ResourceApprovalPolicy.available_actions(
      user: @owner, application: app, team: @team
    )
    assert_includes actions, 'approve_group'
    assert_includes actions, 'reject'
  end

  # ============================================================
  # 6. ProjectApproversPayload
  # ============================================================

  def test_payload_for_owner_lists_projects_and_stages
    clear_approvers!(@project)
    out = Scinote::ElnUi::ProjectApproversPayload.call(user: @owner, team: @team, project_id: @project.id)
    assert_includes out[:projects].map { |p| p[:id] }, @project.id
    assert out[:stages].key?('group'), 'stages 含 group'
    assert out[:stages].key?('project'), 'stages 含 project'
    refute_empty out[:warnings], '未配置阶段 → 红字提示'
  end

  def test_payload_empty_for_non_owner
    member = make_approver_user!
    out = Scinote::ElnUi::ProjectApproversPayload.call(user: member, team: @team)
    assert_empty out[:projects], '非负责人看不到任何可配置项目'
  end

  # ============================================================
  # 7. ProjectApproversController（HTTP）
  # ============================================================

  def test_index_returns_payload_for_owner
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session.get "/eln_project_approvers?project_id=#{@project.id}", headers: { 'ACCEPT' => 'application/json' }
    assert_equal 200, session.response.status
    body = JSON.parse(session.response.body)
    assert_includes body['projects'].map { |p| p['id'] }, @project.id
  end

  def test_create_adds_approver_then_delete_removes
    mate = make_approver_user!
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }

    session.post '/eln_project_approvers',
                 params: { project_id: @project.id, stage: 'group', user_id: mate.id },
                 headers: { 'ACCEPT' => 'application/json' }
    assert_equal 200, session.response.status
    assert Scinote::ElnUi::ProjectApprover.assigned?(project: @project, user: mate, stage: 'group'),
           'POST 后名单应包含该审批人'

    created = Scinote::ElnUi::ProjectApprover.for_project(@project).for_stage('group').for_user(mate).first
    refute_nil created
    session2 = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session2.delete "/eln_project_approvers/#{created.id}"
    assert_equal 200, session2.response.status
    refute Scinote::ElnUi::ProjectApprover.assigned?(project: @project, user: mate, stage: 'group'),
           'DELETE 后名单移除该审批人'
  end

  def test_init_seeds_owners_into_approval_stages_but_not_receipt
    clear_approvers!(@project)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session.post "/eln_project_approvers/init?project_id=#{@project.id}"
    assert_equal 200, session.response.status
    body = JSON.parse(session.response.body)
    assert body['ok']
    assert Scinote::ElnUi::ProjectApprover.assigned?(project: @project, user: @owner, stage: 'group')
    assert Scinote::ElnUi::ProjectApprover.assigned?(project: @project, user: @owner, stage: 'project')
    # 🔴 ADR-0032 D2/D3：验货人是**独立可配**的第三阶段。
    #   「一键初始化」若把负责人也写进验货名单，就等于用一次快捷操作静默决定了
    #   「谁来验别人的货」——而负责人往往就是申请人（自验默认还是关的，
    #   于是配了名单却仍然验不了自己的单，白配）。
    refute Scinote::ElnUi::ProjectApprover.assigned?(project: @project, user: @owner, stage: 'receipt'),
           'init 不得写 receipt 阶段：验货人必须单独指定'
    assert_equal %w[receipt], body['skippedStages']
  end

  def test_index_exposes_receipt_stage_and_policy
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session.get "/eln_project_approvers?project_id=#{@project.id}", headers: { 'ACCEPT' => 'application/json' }
    assert_equal 200, session.response.status
    body = JSON.parse(session.response.body)
    # 面板按 stages 遍历渲染 ⇒ 后端多一个阶段，前端**不改代码**就该出现验货那一栏
    assert_equal %w[group project receipt], body['stages'].keys,
                 '面板阶段集合应与 ProjectApprover::STAGES 一致（前端靠遍历渲染）'
    assert_equal '验货', body['stages']['receipt']['label']
    # 策略随同一次 payload 下发（避免「名单新、开关旧」的撕裂显示）
    assert body.key?('receiptPolicy'), 'payload 应带 receiptPolicy 键'
    refute body['receiptPolicy']['allowSelfVerification'], '默认不允许自验（fail-closed）'
    refute body['receiptPolicy']['persisted'], '从未保存过 ⇒ persisted=false（前端据此说明「用的是默认值」）'
  end

  def test_update_receipt_policy_persists_and_is_idempotent
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session.post '/eln_project_approvers/receipt_policy',
                 params: { project_id: @project.id, allow_self_verification: true },
                 headers: { 'ACCEPT' => 'application/json' }
    assert_equal 200, session.response.status
    assert Scinote::ElnUi::ReceiptPolicy.for_project(@project).allow_self_verification?

    # ⚠ 取消勾选：checkbox 提交的是 "0"/false 这类假值。
    #   若后端用 !!params 会被 truthy 化、把「关」存成「开」——这条就是钉那个坑。
    session.post '/eln_project_approvers/receipt_policy',
                 params: { project_id: @project.id, allow_self_verification: false },
                 headers: { 'ACCEPT' => 'application/json' }
    assert_equal 200, session.response.status
    refute Scinote::ElnUi::ReceiptPolicy.for_project(@project).allow_self_verification?,
           '显式关闭必须真的关掉（不能被 truthy 化）'
    assert_equal 1, Scinote::ElnUi::ReceiptPolicy.where(project_id: @project.id).count,
                 '重复保存应更新同一行，不新增'
  end

  def test_update_receipt_policy_rejected_for_non_owner
    non_owner = make_approver_user!
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(non_owner, scope: :user) }
    session.post '/eln_project_approvers/receipt_policy',
                 params: { project_id: @project.id, allow_self_verification: true },
                 headers: { 'ACCEPT' => 'application/json' }
    assert_equal 403, session.response.status, '非负责人改自验策略应 403'
    refute Scinote::ElnUi::ReceiptPolicy.for_project(@project).allow_self_verification?,
           '被拒的请求不得留下任何写入'
  end

  def test_create_accepts_receipt_stage
    mate = make_approver_user!
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session.post '/eln_project_approvers',
                 params: { project_id: @project.id, stage: 'receipt', user_id: mate.id },
                 headers: { 'ACCEPT' => 'application/json' }
    assert_equal 200, session.response.status
    assert Scinote::ElnUi::ProjectApprover.assigned?(project: @project, user: mate, stage: 'receipt')
  end

  def test_create_rejects_unknown_stage_with_generated_message
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    mate = make_approver_user!
    session.post '/eln_project_approvers',
                 params: { project_id: @project.id, stage: 'final', user_id: mate.id },
                 headers: { 'ACCEPT' => 'application/json' }
    assert_equal 422, session.response.status
    msg = JSON.parse(session.response.body)['error']
    # 报错文案必须由白名单生成：手写「group 或 project」会把合法的 receipt 说成非法
    %w[group project receipt].each { |s| assert_includes msg, s }
    assert_includes msg, '验货'
  end

  def test_create_rejected_for_non_owner
    mate = make_approver_user!
    non_owner = make_approver_user!
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(non_owner, scope: :user) }
    session.post '/eln_project_approvers',
                 params: { project_id: @project.id, stage: 'group', user_id: mate.id },
                 headers: { 'ACCEPT' => 'application/json' }
    # 授权失败必须 403（与 destroy 口径一致），422 只留给业务错误（阶段非法/人不在团队）
    assert_equal 403, session.response.status, '非负责人 POST 应 403 Forbidden'
  end

  def test_init_rejected_for_non_owner
    non_owner = make_approver_user!
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(non_owner, scope: :user) }
    session.post "/eln_project_approvers/init?project_id=#{@project.id}"
    assert_equal 403, session.response.status, '非负责人 init 应 403 Forbidden'
  end

  private

  def can_approve?(user, app, stage, team: @team)
    Scinote::ElnUi::ResourceApprovalPolicy.can_approve?(
      user: user, application: app, stage: stage, team: team
    )
  end

  # 造一个「在团队里、可选配为某项目审批人」的用户（不进 access_control 工厂，本地复用）
  def make_approver_user!(project: nil)
    u = make_user!(name: '审批人')
    join_team!(u, @team)
    configure_approver!(user: u, project: project) if project
    u
  end

  # 造一张资源申请单（与 res_center_test 同款，抽进本类以免跨文件依赖私有方法）
  def make_resource_application!(project:, requestor:, no: nil, status: 'draft', items: nil)
    Scinote::ElnUi::ResourceApplication.create!(
      project: project,
      requestor: requestor,
      no: no || "SQ-2026-#{SecureRandom.hex(4).upcase}",
      status: status,
      # 默认带目标库（ADR-0030 D7）：材料类单子 complete 时要按它到货验收入库
      items: items || [{
        kind: 'material', name: 'PP 基料 K8003', qty: 20, unit: 'kg', unit_price: 350.0,
        repository_id: target_repository_id(team: project.team, creator: requestor)
      }]
    )
  end

  # 与 res_center_test 同款覆盖（基类签名不带 name，build_scene! 走基类时不能传 name）
  def make_project!(team:, creator:, name: nil, visibility: :hidden, strategy: nil)
    ::Project.create!(
      team: team, name: name || "AC project #{SecureRandom.hex(4)}", created_by: creator,
      last_modified_by: creator, visibility: visibility, template: false
    ).tap { |p| p.experiment_visibility_strategy = strategy if strategy && p.respond_to?(:experiment_visibility_strategy=) }
  end
end
