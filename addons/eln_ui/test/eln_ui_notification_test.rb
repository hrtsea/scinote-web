# frozen_string_literal: true

# ELN UI —— 通知中心触发源（报告 §5 第 4 项 #4 · spec SCN-DASH-7 / SCN-TASK-CLOSE-4）
#
# 规格：
#   SCN-DASH-7「当 发生任务指派、任务驳回、任务审核通过、资源申请结果、讨论区新评论、
#     Token 预警或 AI 计算完成，则 系统生成对应消息并推送到通知中心铃铛。」
#   SCN-TASK-CLOSE-4「当 项目负责人驳回关闭申请，则 必须填写驳回理由，任务退回前序状态
#     并通知提交人。」
#
# 实现口径（见 app/services/.../notification_publisher.rb）：
#   走**原生 Notification 表**（GeneralNotification 类型），不造 addon 自有表；
#   不走 send_notifications 工厂（会按未注册的 type 去 constantize Recipients::nil 崩溃），
#   直接 Notification.create!，收件人显式传入。通知是副作用，发布失败 fail-soft 不回滚主流程。
require_relative 'test_helper'

class ElnUiNotificationTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  def setup
    @scene   = build_scene!
    @team    = @scene[:team]
    @project = @scene[:project]
    @creator = @scene[:creator] # 原生建 Project 即挂 owner 角色
    @exp     = make_experiment!(project: @project, creator: @creator)
    @task    = make_task!(experiment: @exp, creator: @creator)
    @owner   = make_user!(name: '项目负责人')
    join_team!(@owner, @team)
    make_project_owner!(@project, user: @owner)
    # 真正的 normal 角色成员当「组员 / 申请人」，避免拿 creator(天然owner) 当非负责人假绿
    @member  = add_member!(@project, @team, assigner: @creator, role: :normal, name: '组员')
    # 审批闸门已 fail-closed：@owner 要真的去批资源申请，就必须先进审批名单
    configure_approver!(user: @owner, project: @project)
  end

  def call_close(user, type, reason: nil)
    Scinote::ElnUi::TaskCloseWorkflow.call(
      user: user, team: @team, my_module_id: @task.id, type: type, reason: reason
    )
  end

  def notif_count(recipient, **like)
    scope = ::Notification.where(recipient: recipient)
    scope = scope.where("params ->> 'message' LIKE ?", "%#{like[:message]}%") if like[:message]
    scope = scope.where("params ->> 'title' LIKE ?", "%#{like[:title]}%") if like[:title]
    scope.count
  end

  # noticed 反序列化后 params 的键可能是符号（ActiveJob::Arguments 序列化语义），
  # 用 indifferent access 同时兼容字符串/符号键，避免读回 nil。
  def params_of(record)
    record.params.with_indifferent_access
  end

  # ---------- 任务关闭：审核通过通知提交人 ----------
  def test_task_close_approve_notifies_submitter
    call_close(@member, 'submit')
    before = notif_count(@member)
    call_close(@owner, 'approve')

    assert_operator notif_count(@member), :>, before, '审核通过后提交人收到一条通知'
    n = ::Notification.where(recipient: @member).order(created_at: :desc).first
    assert_equal 'GeneralNotification', n.type
    assert_includes params_of(n)['title'], '已通过'
    assert_includes params_of(n)['message'], @task.name
  end

  # ---------- 任务关闭：驳回通知提交人（SCN-TASK-CLOSE-4） ----------
  def test_task_close_reject_notifies_submitter_with_reason
    call_close(@member, 'submit')
    call_close(@owner, 'reject', reason: '材料未归档')

    n = ::Notification.where(recipient: @member).order(created_at: :desc).first
    assert_includes params_of(n)['title'], '被驳回'
    assert_includes params_of(n)['message'], '材料未归档', '驳回通知必须带理由'
  end

  # ---------- 任务关闭：未提交则无通知 ----------
  def test_no_notification_before_action
    assert_equal 0, notif_count(@member), '没发生审核动作就不该有通知'
  end

  # ---------- 资源申请：提交通知项目待审人（项目负责人） ----------
  def test_res_apply_submit_notifies_project_owners
    no = create_draft_as(@member)[:no]
    Scinote::ElnUi::ResourceApplicationWorkflow.call(
      user: @member, team: @team, no: no, type: 'submit'
    )

    # @owner 是显式造的项目负责人 → 应收到「待审批」通知
    assert_operator notif_count(@owner, title: '待审批'), :>, 0, '提交后项目负责人收到待审批通知'
  end

  # ---------- 资源申请：初审通过通知申请人 ----------
  def test_res_apply_approve_group_notifies_requestor
    no = create_draft_as(@member)[:no]
    Scinote::ElnUi::ResourceApplicationWorkflow.call(user: @member, team: @team, no: no, type: 'submit')
    before = notif_count(@member)
    Scinote::ElnUi::ResourceApplicationWorkflow.call(user: @owner, team: @team, no: no, type: 'approve_group')

    assert_operator notif_count(@member), :>, before, '初审通过后申请人收到通知'
    n = ::Notification.where(recipient: @member).order(created_at: :desc).first
    assert_includes params_of(n)['title'], '小组初审'
  end

  # ---------- 资源申请：终审通过通知申请人 ----------
  def test_res_apply_approve_project_notifies_requestor
    no = create_draft_as(@member)[:no]
    wf = Scinote::ElnUi::ResourceApplicationWorkflow
    wf.call(user: @member, team: @team, no: no, type: 'submit')
    wf.call(user: @owner, team: @team, no: no, type: 'approve_group')
    before = notif_count(@member)
    wf.call(user: @owner, team: @team, no: no, type: 'approve_project')

    assert_operator notif_count(@member), :>, before, '终审通过后申请人收到通知'
    assert_includes params_of(::Notification.where(recipient: @member).order(created_at: :desc).first)['title'], '终审'
  end

  # ---------- 资源申请：驳回通知申请人（带理由） ----------
  def test_res_apply_reject_notifies_requestor_with_reason
    no = create_draft_as(@member)[:no]
    wf = Scinote::ElnUi::ResourceApplicationWorkflow
    wf.call(user: @member, team: @team, no: no, type: 'submit')
    wf.call(user: @owner, team: @team, no: no, type: 'reject', reason: '预算不足')

    n = ::Notification.where(recipient: @member).order(created_at: :desc).first
    assert_includes params_of(n)['title'], '被驳回'
    assert_includes params_of(n)['message'], '预算不足', '驳回通知必须带理由'
  end

  # ---------- 通知是原生表、且 fail-soft（收件人不存在不炸主流程） ----------
  def test_publisher_uses_native_table_and_is_fail_soft
    # 收件人是 nil / 不存在 id → 静默返回 nil，不抛错
    assert_nil Scinote::ElnUi::NotificationPublisher.notify(nil, title: 'x', message: 'y')
    assert_nil Scinote::ElnUi::NotificationPublisher.notify(99_999_999, title: 'x', message: 'y')

    # 正常路径落原生 Notification 表
    u = make_user!(name: '收件人')
    rec = Scinote::ElnUi::NotificationPublisher.notify(u, title: '你好', message: '世界')
    refute_nil rec
    assert_equal 'GeneralNotification', rec.type
    assert_equal '你好', params_of(rec)['title']
  end

  private

  def create_draft_as(user)
    Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: user, team: @team, project_id: @project.id,
      kind: 'material', name: '试剂', qty: 2, unit_price: 100,
      # 材料类必填目标库（ADR-0030 D7）
      repository_id: target_repository_id(team: @team, creator: user)
    )
  end
end
