# frozen_string_literal: true
#
# D5 —— 「一键补回继承」
#
# 实测推翻了词汇表 §14「必须存快照才能自动化回滚」的设想：
# 本 addon 的隔离是「在 job 里拦截复制」而**不是删行**，所以「该补谁、补什么角色」
# 都能从 Project 现有的 UA 直接推导 —— 不需要独立快照表，重跑一遍
# InheritUserAssignmentsJob 即可。
#
# 安全边界：job 第 96 行 `return if manually_assigned?`，所以 PI 显式放行过的格子
# 不会被补回覆盖。

require_relative 'test_helper'

class D5BackfillTest < AcTest::Base
  def test_backfill_refuses_while_isolated
    scene = build_scene!(strategy: :isolated)

    result = scene[:project].backfill_inherited_assignments!(by: scene[:creator])

    assert_equal :not_inherit, result[:skipped],
                 'isolated 下不该提供「一键补继承」——那等于给个自相矛盾的按钮'
  end

  def test_backfill_restores_both_experiments_and_tasks
    scene  = build_scene!(strategy: :isolated)
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])
    task   = make_task!(experiment: exp, creator: scene[:creator])

    refute can_read?(exp, member),  '前置：isolated 下成员看不到'
    refute can_read?(task, member), '前置：任务也看不到'

    scene[:project].ac_visibility_strategy = :inherit
    result = scene[:project].backfill_inherited_assignments!(by: scene[:creator])

    assert result[:backfilled], "补回应成功，实际：#{result.inspect}"
    assert_equal 1, result[:experiments]
    assert_equal 1, result[:tasks]

    assert can_read?(exp, member),  '补回后实验应可见'
    assert can_read?(task, member), '补回后任务也应可见（只补实验会得一个空壳）'
  end

  def test_backfill_does_not_clobber_manual_grants
    scene  = build_scene!(strategy: :isolated)
    member = add_restricted_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])

    grant!(exp, member) # PI 在隔离期间显式放过这一格
    manual_role = ua_for(exp, member).user_role.name
    assert_equal 'manually', ua_for(exp, member).assigned

    scene[:project].ac_visibility_strategy = :inherit
    scene[:project].backfill_inherited_assignments!(by: scene[:creator])

    row = ua_for(exp, member)
    assert_equal manual_role, row.user_role.name, '手动放行过的格子不该被补回覆盖'
    assert_equal 'manually', row.assigned
  end

  def test_backfill_needs_an_assigner
    scene = build_scene!(strategy: :inherit)

    result = scene[:project].backfill_inherited_assignments!(by: nil)

    assert_equal :no_assigner, result[:skipped]
  end
end
