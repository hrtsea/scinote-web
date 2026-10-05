# frozen_string_literal: true
#
# D3 —— creator 自动可见性（建了就能看见自己的东西）
#
# 关键点：这里用的是「升级语义」而不是「有任意 UA 就跳过」。
# 因为项目下放会先给 Experiment 造一条 automatically 的 Owner 行，
# 若按「有行就跳过」判断，creator 钩子将永远被饿死。

require_relative 'test_helper'

class D3CreatorVisibilityTest < AcTest::Base
  def test_creator_gets_experiment_owner_role_on_own_experiment
    scene = build_scene!
    exp   = make_experiment!(project: scene[:project], creator: scene[:creator])
    row   = ua_for(exp, scene[:creator])

    assert row, 'creator 在自己的实验上应有 UA'
    assert_equal 'experiment_owner', row.user_role.name
    assert_equal 'manually', row.assigned, 'creator 行必须是 manually（免疫异步 job 覆盖）'
    assert can_read?(exp, scene[:creator])
  end

  def test_creator_gets_task_owner_role_on_own_task
    scene = build_scene!
    exp   = make_experiment!(project: scene[:project], creator: scene[:creator])
    task  = make_task!(experiment: exp, creator: scene[:creator])
    row   = ua_for(task, scene[:creator])

    assert row, 'creator 在自己的任务上应有 UA'
    assert_equal 'task_owner', row.user_role.name
    assert can_read?(task, scene[:creator])
  end

  def test_existing_row_is_upgraded_in_place_not_duplicated
    scene = build_scene!
    exp   = make_experiment!(project: scene[:project], creator: scene[:creator])

    rows = UserAssignment.where(assignable_type: 'Experiment',
                                assignable_id: exp.id,
                                user_id: scene[:creator].id)

    assert_equal 1, rows.count,
                 '同一 (assignable,user,team) 只能有一行 —— 唯一索引不含 role，必须 update 不能 create'
    assert_equal 'experiment_owner', rows.first.user_role.name
  end

  def test_creator_visibility_survives_the_async_inherit_job
    scene = build_scene!
    exp   = make_experiment!(project: scene[:project], creator: scene[:creator])

    # 再跑一次继承 job：manually 行必须免疫（job:96 `return if manually_assigned?`）
    UserAssignments::InheritUserAssignmentsJob.perform_now(exp, assigner_id: scene[:creator].id)
    row = ua_for(exp, scene[:creator])

    assert_equal 'experiment_owner', row.user_role.name, '手动行不应被异步 job 降级'
    assert_equal 'manually', row.assigned
  end

  def test_other_member_is_unaffected_by_creator_hook
    scene  = build_scene!
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])

    row = ua_for(exp, member)
    refute_equal 'experiment_owner', row&.user_role&.name,
                 'D3 只补 creator，不该顺手把别人提成 owner'
  end
end
