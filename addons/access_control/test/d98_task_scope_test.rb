# frozen_string_literal: true
#
# D9.8 —— 任务级放行（scope=:task）
#
# 为什么需要它：permission_granted? 只查对象自身 UA，绝不向上走父级
# （permission_checkable_model.rb:49-65）。所以「实验可见」推导不出「任务可见」——
# PI 只勾实验，成员能进门却干不了活。
#
# 实现：WL-实验+任务可见（含 task_read）。放实验上 = 实验可见 +「含任务」标记；
# 放 MyModule 上 = 任务可见。一个角色两处复用。

require_relative 'test_helper'

class D98TaskScopeTest < AcTest::Base
  def setup_scene
    @scene  = build_scene!
    @exp    = make_experiment!(project: @scene[:project], creator: @scene[:creator])
    @task   = make_task!(experiment: @exp, creator: @scene[:creator])
    @member = add_restricted_member!(@scene[:project], @scene[:team], assigner: @scene[:creator])
  end

  def test_experiment_scope_opens_experiment_but_not_tasks
    setup_scene

    grant!(@exp, @member, scope: :experiment)

    assert can_read?(@exp, @member),  '实验应可见'
    refute can_read?(@task, @member), '任务不该跟着可见 —— 这正是 D9.8 存在的理由'
  end

  def test_task_scope_opens_both_experiment_and_tasks
    setup_scene

    assert grant!(@exp, @member, scope: :task)

    assert can_read?(@exp, @member),  '实验应可见'
    assert can_read?(@task, @member), '任务也应可见'
  end

  def test_task_scope_materialises_rows_on_each_task
    setup_scene
    task2 = make_task!(experiment: @exp, creator: @scene[:creator])

    grant!(@exp, @member, scope: :task)

    [@task, task2].each do |t|
      row = ua_for(t, @member)
      assert row, "任务 #{t.id} 上应落一行"
      assert_equal 'WL-实验+任务可见', row.user_role.name
    end
  end

  def test_revoking_task_scope_keeps_experiment_visible
    setup_scene
    grant!(@exp, @member, scope: :task)
    assert can_read?(@task, @member), '前置：任务可见'

    revoke!(@exp, @member, scope: :task)

    refute can_read?(@task, @member), '任务应收回去'
    assert can_read?(@exp, @member),  '实验仍可见 —— PI 只是不想让人碰任务'
  end

  def test_task_row_is_downgraded_back_to_wl_on_revoke
    setup_scene
    grant!(@exp, @member, scope: :task)
    assert_equal 'WL-实验+任务可见', ua_for(@exp, @member).user_role.name

    revoke!(@exp, @member, scope: :task)

    assert_equal 'WL-实验可见(含画布)', ua_for(@exp, @member).user_role.name,
                 '实验上那条要降级回 WL（去掉 task_read，保留实验可见）'
  end

  def test_new_task_created_after_task_grant_is_visible
    setup_scene
    grant!(@exp, @member, scope: :task)

    # 放行之后新建的任务应自动继承（job 复制父级行的 user_role）
    new_task = make_task!(experiment: @exp, creator: @scene[:creator])

    assert can_read?(new_task, @member), '放行后新建的任务应自动继承可见性'
  end
end
