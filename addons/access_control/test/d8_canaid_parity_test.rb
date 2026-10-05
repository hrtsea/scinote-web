# frozen_string_literal: true
#
# D8 —— Canaid 与 UserAssignment 是「同一数据源的两层」
#
# 结论（钉死，别再重新推导）：
#   Canaid 不是独立的第二套权限系统，它只是 UA 的**包装层**：
#     app/permissions/experiment.rb: can :read_experiment { exp.permission_granted?(user, ExperimentPermissions::READ) }
#   所以「放行 UA」==「Canaid 自动跟上」，addon **不需要**往 app/permissions 注册任何东西。
#
# 这一组测试是**架构性护栏**：如果将来有人以为要另注册权限而做无用功，或者上游把
# Canaid 改成绕过 UA 的独立实现，这里会立刻报警。

require_relative 'test_helper'

class D8CanaidParityTest < AcTest::Base
  def holder
    Canaid::PermissionsHolder.instance
  end

  # eval(name, user, obj) —— 与 Controller/View 里 can_read_experiment?(...) 走同一条路径
  def canaid_read_experiment(user, experiment)
    holder.eval('read_experiment', user, experiment)
  end

  def canaid_read_task(user, task)
    holder.eval('read_my_module', user, task)
  end

  def test_canaid_and_ua_agree_before_any_grant
    scene   = build_scene!
    member  = add_restricted_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp     = make_experiment!(project: scene[:project], creator: scene[:creator])

    ua     = exp.permission_granted?(member, ExperimentPermissions::READ)
    canaid = canaid_read_experiment(member, exp)

    assert_equal false, ua,     '前置：受限成员在实验上无 UA 读权限'
    assert_equal ua, canaid,    'Canaid 结论必须与 UA 一致（同为 false）'
  end

  def test_granting_ua_makes_canaid_follow_automatically
    scene  = build_scene!
    member = add_restricted_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])

    grant!(exp, member)
    exp.reload

    assert exp.permission_granted?(member, ExperimentPermissions::READ),
           '放行后 UA 应为可读'
    assert canaid_read_experiment(member, exp),
           '放行 UA 后 Canaid 应自动跟上（无需 addon 注册权限）'
  end

  def test_task_scope_grant_flows_into_canaid
    scene  = build_scene!
    member = add_restricted_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])
    task   = make_task!(experiment: exp, creator: scene[:creator])

    grant!(exp, member, scope: :task)
    task.reload

    assert task.permission_granted?(member, MyModulePermissions::READ),
           '任务级放行后 UA 应可读任务'
    assert canaid_read_task(member, task),
           '任务级放行后 Canaid 的 read_my_module 也应跟上'
  end

  def test_experiment_scope_grant_does_not_leak_into_task
    scene  = build_scene!
    member = add_restricted_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])
    task   = make_task!(experiment: exp, creator: scene[:creator])

    grant!(exp, member, scope: :experiment)

    assert canaid_read_experiment(member, exp), '实验级：实验可见'
    refute canaid_read_task(member, task),
           '实验级放行不该带出任务可见 —— 实验可见 ≠ 任务可见'
  end

  def test_the_two_namespaces_are_not_interchangeable
    # Canaid 注册名：动词在前；UserRole.permissions / *Permissions 常量：名词在前。
    assert holder.has_permission?('read_experiment'),
           "Canaid 侧应注册 'read_experiment'"
    refute holder.has_permission?('experiment_read'),
           "'experiment_read' 是 UA 侧权限名，Canaid 里查不到（别张冠李戴）"

    assert_equal 'experiment_read', ExperimentPermissions::READ
    assert_equal 'task_read',       MyModulePermissions::READ
  end

  def test_addon_registers_no_canaid_permission_of_its_own
    # D8 的核心含义：addon 不需要（也确实没有）往 app/permissions 塞东西。
    # 若哪天这里出现文件，说明有人在重复造轮子 —— 先回来读这份测试。
    dir = Rails.root.join('addons/access_control/app/permissions')
    refute dir.exist?,
           "addon 不应自带 Canaid 权限注册（#{dir}）——放行 UA 即自动生效"
  end

  def test_revoking_ua_also_turns_canaid_off
    scene  = build_scene!
    member = add_restricted_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])

    grant!(exp, member)
    assert canaid_read_experiment(member, exp), '前置：已放行'

    revoke!(exp, member)
    exp.reload

    refute exp.permission_granted?(member, ExperimentPermissions::READ), '收回后 UA 不可读'
    refute canaid_read_experiment(member, exp),
           '收回后 Canaid 也应同步关闭（两层始终同源）'
  end
end
