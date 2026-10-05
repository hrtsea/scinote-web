# frozen_string_literal: true
#
# D2 —— 项目级可见性策略开关（inherit / isolated）
#
# 核心事实：策略**只影响新建对象**（切回 inherit 不会自动补回存量，那是 D5 的活），
# 拦截点在 `InheritUserAssignmentsJob#assign_to_experiment`（prepend 覆盖），
# 而不是 after_create 删行 —— 因为 job 是异步的，删了也会被它后跑补回来。

require_relative 'test_helper'

class D2VisibilityStrategyTest < AcTest::Base
  def test_isolated_blocks_new_experiment_from_ordinary_member
    scene  = build_scene!(strategy: :isolated)
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])

    refute can_read?(exp, member), 'isolated 下新建实验不该被普通成员看到'
  end

  def test_inherit_propagates_new_experiment_to_ordinary_member
    scene  = build_scene!(strategy: :inherit)
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])

    assert can_read?(exp, member), 'inherit 下新建实验应被普通成员看到'
  end

  def test_isolated_never_blocks_the_creator
    scene = build_scene!(strategy: :isolated)
    exp   = make_experiment!(project: scene[:project], creator: scene[:creator])

    assert can_read?(exp, scene[:creator]), '隔离不能把创建者本人挡在外面'
  end

  def test_strategy_defaults_to_inherit
    scene = build_scene! # 不显式设策略

    assert scene[:project].inherit?, '默认策略应为 inherit'
    refute scene[:project].isolated?
  end

  def test_switching_strategy_does_not_rewrite_existing_experiments
    scene  = build_scene!(strategy: :isolated)
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])
    refute can_read?(exp, member), '前置：isolated 下看不到'

    # 切回 inherit —— 存量实验**不会**自动补回（这正是 D5 存在的理由）
    scene[:project].update!(experiment_visibility_strategy: :inherit)
    exp.reload

    refute can_read?(exp, member), '切回 inherit 后存量实验仍不可见（开关只管新建）'
  end

  def test_new_experiment_after_switch_to_inherit_is_visible
    scene  = build_scene!(strategy: :isolated)
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator])
    scene[:project].update!(experiment_visibility_strategy: :inherit)

    exp2 = make_experiment!(project: scene[:project], creator: scene[:creator])

    assert can_read?(exp2, member), '切回 inherit 之后新建的实验应可见'
  end
end
