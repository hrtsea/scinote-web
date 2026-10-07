# frozen_string_literal: true

# ELN UI —— 任务关闭审核（REQ-TASK-CLOSE / SCN-TASK-CLOSE-1..4 · DEC-003）
#
# 规格（spec V1.23 L769-788）：
#   「实验任务标记『已关闭』**必须且只能**由项目负责人审核通过触发。
#     组员不可关闭任务；小组组长可新建/指派任务但不可审核关闭。」
#   SCN-TASK-CLOSE-1 待审核 + 项目负责人通过 → 已关闭
#   SCN-TASK-CLOSE-2 组员不提供关闭/审核关闭入口
#   SCN-TASK-CLOSE-3 小组组长不提供审核关闭入口
#   SCN-TASK-CLOSE-4 驳回必须填理由，任务退回前序状态
#
# 这里钉的不只是流程能跑，还有三条容易悄悄塌掉的：
#   ① 「项目负责人」必须是**宿主原生 owner 角色**，不是 eln_ui_task_profiles.owner_user
#      （后者是任务级展示字段，拿它当审核权 = 谁被指派谁就能关自己的任务）；
#   ② 审核权判定取不到时必须 **fail-closed**（当成非负责人）——「判不出来就放行」
#      是权限代码里最贵的一个 bug；
#   ③ 端点必须真打过（Integration::Session），因为 eln_res_applications 当初就是
#      「一存在就 500、而 92 条用例全绿」——因为没人打过它。
require_relative 'test_helper'

class ElnUiTaskCloseTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  def setup
    @scene   = build_scene!
    @team    = @scene[:team]
    @project = @scene[:project]
    @creator = @scene[:creator]
    @exp     = make_experiment!(project: @project, creator: @creator)
    @task    = make_task!(experiment: @exp, creator: @creator)
    @owner   = make_user!(name: '项目负责人')
    # ⚠ 光设 current_team_id 没用：ApplicationController#current_team 走
    #   `current_user.teams.find_by(id: current_user.current_team_id)` ——
    #   人没真正入队 team，find_by 就是 nil → check_team_membership 403。
    #   join_team! 本身会建 Team 级 UserAssignment 并 update current_team_id。
    join_team!(@owner, @team)
    # ⚠ scene[:creator] **不能**拿来当「组员」：原生建 Project 时会自动给创建者挂
    #   predefined owner 角色（实测 creator 就是 reviewer），拿它当非负责人会得到假绿。
    #   这里另造一个真正的 normal 角色成员当组员。
    @member  = add_member!(@project, @team, assigner: @creator, role: :normal, name: '组员')
  end

  def call_flow(user, type, reason: nil, my_module: @task)
    Scinote::ElnUi::TaskCloseWorkflow.call(
      user: user, team: @team, my_module_id: my_module.id, type: type, reason: reason
    )
  end

  # Canaid 的 method_missing 吞掉一切非 can_*? 方法，assert_nothing_raised 会直接
  # NoMethodError（老坑）。自己捕获，别用那个断言。
  def caught_error
    yield
    nil
  rescue StandardError => e
    e
  end

  # ============================================================
  # 提交（谁在干活谁就能提）
  # ============================================================

  def test_member_can_submit_close_request
    result = call_flow(@creator, 'submit')

    assert_equal true, result[:ok]
    assert_equal 'pending', result[:state]
    assert_equal '待审核', result[:stateLabel]

    req = Scinote::ElnUi::TaskCloseRequest.latest_for(@task)
    refute_nil req, '提交必须真落一行（不只是回包）'
    assert_equal @creator.id, req.submitted_by_id
    assert_nil req.reviewer_id, '提交时不该有审核人'
  end

  # 已在审时重复提交要挡住 —— 否则一个任务能堆出多条待审，审核人无从下手
  def test_duplicate_submit_is_rejected
    call_flow(@creator, 'submit')
    err = caught_error { call_flow(@creator, 'submit') }

    assert_kind_of Scinote::ElnUi::Workflow::WorkflowError, err
    assert_includes err.message, '已有待审核'
    assert_equal 1, Scinote::ElnUi::TaskCloseRequest.where(my_module_id: @task.id).count
  end

  # 已关闭不再受理提交（spec 只定义了「关闭」这一个终态，没定义「重开」）
  def test_submit_after_close_is_rejected
    make_project_owner!(@project, user: @owner)
    call_flow(@creator, 'submit')
    call_flow(@owner, 'approve')

    err = caught_error { call_flow(@creator, 'submit') }
    assert_includes err.message, '已关闭'
  end

  # 跨团队提交要挡住：check_team_membership 只保证「在某个团队里」，
  # 不保证「在这个项目的团队里」
  def test_cross_team_submit_is_rejected
    other = Team.create!(name: "t2-#{SecureRandom.hex(3)}", created_by: @creator)
    err = caught_error do
      Scinote::ElnUi::TaskCloseWorkflow.call(
        user: @creator, team: other, my_module_id: @task.id, type: 'submit', reason: nil
      )
    end

    assert_includes err.message, '仅同团队成员'
  end

  # ============================================================
  # SCN-TASK-CLOSE-1：待审核 + 项目负责人通过 → 已关闭
  # ============================================================

  def test_owner_approve_closes_task
    make_project_owner!(@project, user: @owner)
    call_flow(@creator, 'submit')

    result = call_flow(@owner, 'approve')

    assert_equal true, result[:ok]
    assert_equal 'approved', result[:state]
    assert_equal '已关闭', result[:stateLabel]
    assert_equal true, Scinote::ElnUi::TaskCloseRequest.closed?(@task)

    req = Scinote::ElnUi::TaskCloseRequest.latest_for(@task)
    assert_equal @owner.id, req.reviewer_id, '审核人必须留痕'
    refute_nil req.reviewed_at
  end

  # ============================================================
  # SCN-TASK-CLOSE-2 / -3：组员与小组组长都不可审核关闭
  # ============================================================

  # SCN-TASK-CLOSE-2：组员（normal 角色，非 owner）不能审核关闭
  def test_plain_member_cannot_approve
    call_flow(@member, 'submit')
    err = caught_error { call_flow(@member, 'approve') }

    assert_includes err.message, '仅项目负责人可审核关闭'
    assert_equal false, Scinote::ElnUi::TaskCloseRequest.closed?(@task), '越权不能改状态'
    assert_equal 'pending', Scinote::ElnUi::TaskCloseRequest.latest_for(@task).status
  end

  # 小组组长有 owner 以外的角色，**不是** predefined owner role → 一样不能审
  def test_group_leader_cannot_approve
    leader = make_user!(name: '小组组长')
    ua = UserAssignment.find_or_initialize_by(user: leader, assignable: @project, team_id: @team.id)
    ua.update!(user_role: UserRole.find_predefined_normal_user_role, assigned: :manually)

    call_flow(@member, 'submit')
    err = caught_error { call_flow(leader, 'approve') }

    assert_includes err.message, '仅项目负责人可审核关闭'
    refute Scinote::ElnUi::TaskCloseWorkflow.reviewer?(leader, @task)
  end

  # 审核权判定的 fail-closed 方向：查不到角色 / 查不到人 → 一律当「不是负责人」。
  # 宁可没人能审，也不能「判不出来就放行」。
  def test_reviewer_predicate_fails_closed
    assert_equal false, Scinote::ElnUi::TaskCloseWorkflow.reviewer?(nil, @task)
    assert_equal false, Scinote::ElnUi::TaskCloseWorkflow.reviewer?(@member, nil)
    assert_equal false, Scinote::ElnUi::TaskCloseWorkflow.reviewer?(@owner, @task),
                 '还没被指派成负责人时不得放行'
    assert_equal false, Scinote::ElnUi::TaskCloseWorkflow.reviewer?(@member, @task),
                 'normal 角色成员不是审核人'

    make_project_owner!(@project, user: @owner)
    assert_equal true, Scinote::ElnUi::TaskCloseWorkflow.reviewer?(@owner, @task)
  end

  # 审核权只认**本任务所属项目**的负责人：把 A 项目负责人指派成 B 项目负责人，
  # 不该能审 A 项目的任务（project_id 取错就会穿模，故这里用一个真实同团队项目对拍）。
  def test_owner_of_other_project_cannot_approve
    other_project = make_project!(team: @team, creator: @creator)
    make_project_owner!(other_project, user: @owner)
    refute_equal @task.experiment.project_id, other_project.id, '前提：确实是另一个项目'

    call_flow(@creator, 'submit')
    err = caught_error { call_flow(@owner, 'approve') }

    assert_includes err.message, '仅项目负责人可审核关闭'
    assert_equal false, Scinote::ElnUi::TaskCloseRequest.closed?(@task)
  end

  # 没有待审核行时 approve 必须报错，而不是静默成功（否则前端一次误点就「关」了）
  def test_approve_without_pending_request_is_rejected
    make_project_owner!(@project, user: @owner)
    err = caught_error { call_flow(@owner, 'approve') }

    assert_includes err.message, '没有待审核'
  end

  # ============================================================
  # SCN-TASK-CLOSE-4：驳回必填理由
  # ============================================================

  def test_reject_without_reason_is_rejected
    make_project_owner!(@project, user: @owner)
    call_flow(@creator, 'submit')

    err = caught_error { call_flow(@owner, 'reject', reason: '') }

    assert_includes err.message, '必须填写驳回理由'
    req = Scinote::ElnUi::TaskCloseRequest.latest_for(@task)
    assert_equal 'pending', req.status, '驳回失败必须仍是待审核，不能半改'
  end

  def test_reject_with_reason_marks_rejected_and_keeps_trail
    make_project_owner!(@project, user: @owner)
    call_flow(@creator, 'submit')

    result = call_flow(@owner, 'reject', reason: '表征数据未回填')

    assert_equal 'rejected', result[:state]
    assert_equal '已驳回', result[:stateLabel]
    assert_equal false, Scinote::ElnUi::TaskCloseRequest.closed?(@task), '驳回 ≠ 关闭'

    req = Scinote::ElnUi::TaskCloseRequest.latest_for(@task)
    assert_equal '表征数据未回填', req.reason
    assert_equal @owner.id, req.reviewer_id
  end

  # 驳回后可以再次提交，且**新起一行** —— 历史留痕不能被覆盖
  def test_resubmit_after_reject_creates_new_row
    make_project_owner!(@project, user: @owner)
    call_flow(@creator, 'submit')
    call_flow(@owner, 'reject', reason: '数据没回填')

    call_flow(@creator, 'submit')

    rows = Scinote::ElnUi::TaskCloseRequest.where(my_module_id: @task.id).order(:id)
    assert_equal 2, rows.count, '驳回后重提要留下两行历史'
    assert_equal %w[rejected pending], rows.map(&:status)
    assert_equal 'pending', Scinote::ElnUi::TaskCloseRequest.latest_for(@task).status
  end

  # 模型层再钉一次：驳回没理由直接建行也不许（防止有别的写入方绕过 workflow）
  def test_model_rejects_rejection_without_reason
    err = caught_error do
      make_task_close_request!(my_module: @task, submitted_by: @creator, status: 'rejected')
    end

    assert_kind_of ActiveRecord::RecordInvalid, err
    assert_includes err.message, '驳回'
  end

  # ============================================================
  # 未知动作 / 任务不存在
  # ============================================================

  def test_unknown_action_is_rejected
    err = caught_error { call_flow(@creator, 'destroy_everything') }
    assert_includes err.message, '未知操作'
  end

  def test_missing_task_is_rejected
    err = caught_error do
      Scinote::ElnUi::TaskCloseWorkflow.call(
        user: @creator, team: @team, my_module_id: 0, type: 'submit', reason: nil
      )
    end

    assert_includes err.message, '任务不存在'
  end

  # ============================================================
  # 与资源申请共用同一套骨架（这是抽 Workflow 的全部理由）
  # ============================================================

  def test_both_workflows_share_one_error_class
    assert_equal Scinote::ElnUi::Workflow::WorkflowError,
                 Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError
    assert_equal Scinote::ElnUi::Workflow::WorkflowError,
                 Scinote::ElnUi::TaskCloseWorkflow::WorkflowError
    assert_operator Scinote::ElnUi::TaskCloseWorkflow, :<, Scinote::ElnUi::Workflow
    assert_operator Scinote::ElnUi::ResourceApplicationWorkflow, :<, Scinote::ElnUi::Workflow
  end

  def test_workflow_actions_are_whitelisted
    assert_equal %w[submit approve reject], Scinote::ElnUi::TaskCloseWorkflow.actions
    assert_includes Scinote::ElnUi::ResourceApplicationWorkflow.actions, 'submit'
  end

  # ============================================================
  # payload closeReview（前端入口的判据，后端与页面判的是同一处）
  # ============================================================

  def test_payload_close_review_block_for_owner
    make_project_owner!(@project, user: @owner)
    call_flow(@creator, 'submit')

    block = Scinote::ElnUi::MyModuleDetailPayload.call(@task, @owner)[:closeReview]

    assert_equal true, block[:available]
    assert_equal 'pending', block[:state]
    assert_equal '待审核', block[:stateLabel]
    assert_equal false, block[:closed]
    assert_equal true, block[:canReview], '有待审 + 是负责人 → 给审核入口'
    assert_equal false, block[:canSubmit], '已在审就别再给提交入口'
    assert_equal "/eln_task_close/#{@task.id}/actions", block[:actionsUrl]
    assert_includes block[:note], '待项目负责人审核'
  end

  def test_payload_close_review_block_for_member_has_no_review_entry
    call_flow(@member, 'submit')

    block = Scinote::ElnUi::MyModuleDetailPayload.call(@task, @member)[:closeReview]

    assert_equal false, block[:canReview], '组员不给审核入口（SCN-TASK-CLOSE-2）'
    assert_includes block[:note], '当前身份不可审核'
    assert_nil block[:reviewerName], '还没人审 → 留白，不能编个人名'
    assert_equal "/eln_task_close/#{@task.id}/actions", block[:actionsUrl]
  end

  def test_payload_close_review_block_before_any_request
    block = Scinote::ElnUi::MyModuleDetailPayload.call(@task, @member)[:closeReview]

    assert_equal 'none', block[:state]
    assert_equal '未提交关闭申请', block[:stateLabel]
    assert_equal true, block[:canSubmit], '没提交过就该给提交入口'
    assert_equal false, block[:canReview]
  end

  # ★ 关键：review.canReview 现在取的是**真口径**（项目负责人），
  #   以前是拿 canManageTask 近似 —— 组员/组长会拿到不该有的审核位。
  #   canManageTask 本身是 controller 传进来的入参（默认 false），故这里显式传 true
  #   来证明「换了 canReview 的来源，但没有顺手把这个字段改成别的东西」。
  def test_review_can_review_uses_real_owner_check
    call_flow(@member, 'submit')

    member_review = Scinote::ElnUi::MyModuleDetailPayload.call(
      @task, @member, can_manage_task: true
    )[:review]
    assert_equal false, member_review[:canReview], '组员 review.canReview 必须是 false'
    assert_equal true, member_review[:canManageTask], 'canManageTask 仍由入参决定，不被 canReview 顶掉'
    assert_includes member_review[:hint], '项目负责人'

    make_project_owner!(@project, user: @owner)
    owner_review = Scinote::ElnUi::MyModuleDetailPayload.call(@task, @owner)[:review]
    assert_equal true, owner_review[:canReview], '项目负责人拿到审核位'
  end

  # ============================================================
  # 端点 POST /eln_task_close/:my_module_id/actions
  # ============================================================

  def post_action(my_module, type, reason: nil)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session.post "/eln_task_close/#{my_module.id}/actions",
                 params: { type: type, reason: reason }.to_json,
                 headers: { 'CONTENT_TYPE' => 'application/json' }
    body = (JSON.parse(session.response.body) rescue {})
    [session.response.status, body]
  end

  def test_endpoint_approve_returns_ok
    make_project_owner!(@project, user: @owner)
    call_flow(@creator, 'submit')

    status, body = post_action(@task, 'approve')

    assert_equal 200, status, "body=#{body}"
    assert_equal true, body['ok']
    assert_equal 'approved', body['state']
    assert_equal Scinote::ElnUi::TaskCloseRequest.closed?(@task), true
  end

  # WorkflowError 一律 422，绝不能漏成 500（当年 eln_res_applications 就是这么红的）
  def test_endpoint_business_error_returns_422_not_500
    call_flow(@creator, 'submit') # owner 还没被指派 → 审核应被拒

    status, body = post_action(@task, 'approve')

    assert_equal 422, status, "body=#{body}"
    assert_equal false, body['ok']
    assert_includes body['error'].to_s, '仅项目负责人可审核关闭'
  end

  def test_endpoint_reject_without_reason_returns_422
    make_project_owner!(@project, user: @owner)
    call_flow(@creator, 'submit')

    status, body = post_action(@task, 'reject', reason: '')

    assert_equal 422, status, "body=#{body}"
    assert_includes body['error'].to_s, '必须填写驳回理由'
  end

  def test_endpoint_unknown_type_returns_422
    status, body = post_action(@task, 'nonsense')

    assert_equal 422, status, "body=#{body}"
    assert_includes body['error'].to_s, '未知操作'
  end
end
