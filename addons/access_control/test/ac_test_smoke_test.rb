# frozen_string_literal: true
#
# 基础设施自检 —— 先于所有业务测试跑通。
# 验的是「环境搭起来了没有」：策略列、角色 seed、以及能否凭空搭出一个场景。
# 它挂了说明是测试环境问题，不是 addon 回归。

require_relative 'test_helper'

class AcTestSmokeTest < AcTest::Base
  def test_strategy_column_exists
    cols = ActiveRecord::Base.connection.columns(:projects).map(&:name)
    assert_includes cols, 'experiment_visibility_strategy'
  end

  def test_predefined_roles_exist
    assert UserRole.predefined.exists?(name: 'Owner'), 'Owner 预定义角色缺失'
  end

  def test_all_custom_roles_seeded
    AcTest::CUSTOM_ROLES.each_key do |name|
      refute_nil AcTest.role(name), "自定义角色 #{name} 未 seed"
    end
  end

  def test_wl_task_role_has_task_read
    role = AcTest.role('WL-实验+任务可见')
    assert_includes role.permissions, 'task_read'
    assert_includes role.permissions, 'experiment_read'
  end

  def test_can_build_a_scene_from_scratch
    scene   = build_scene!
    creator = scene[:creator]
    exp     = make_experiment!(project: scene[:project], creator: creator)
    task    = make_task!(experiment: exp, creator: creator)

    assert can_read?(scene[:project], creator), 'creator 应能读自己的项目'
    assert can_read?(exp, creator),             'creator 应能读自己的实验（D3 锚点）'
    assert can_read?(task, creator),            'creator 应能读自己的任务（D3 锚点）'
  end

  # 验证「每个 test 独立事务、跑完即回滚」这件事本身。
  # 刻意**不**写成「断言库里 AC project 总数为 0」——那依赖全局状态和执行顺序，
  # 一旦有诊断脚本在事务外留下脏数据就会假失败。改成在 test 内部开一个
  # requires_new 的 savepoint，自己回滚、自己验证，完全自包含。
  def test_scene_data_is_rolled_back
    leaked_id = nil

    ActiveRecord::Base.transaction(requires_new: true) do
      leaked_id = build_scene![:project].id
      assert Project.exists?(leaked_id), 'savepoint 内应能看到刚建的项目'
      raise ActiveRecord::Rollback
    end

    refute Project.exists?(leaked_id), '回滚后不应还能看到该项目 —— 事务隔离失效'
  end
end
