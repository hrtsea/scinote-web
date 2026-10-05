# frozen_string_literal: true
#
# D9 / D9.7 —— 项目负责人（PI）
#
# 原生只把 supervised_by_id 写进活动流（377/378），**根本不给权限** ——
# 所谓「项目负责人」在权限上等于普通人。本 addon 把它接上：
#   - 设 PI   → 在 Project 上 upsert 一条 project_head（含 project_manage）手动行，并下放子对象
#   - 换 PI   → 旧 PI 的那一行 + 其在子对象上的物化行一并收回
#
# 收回时必须**只删本钩子造的行**：按 user_id 一刀切会把 D3 给 creator 的锚点、
# 以及成员自己被显式放行的行一起抹掉。

require_relative 'test_helper'

class D9ProjectHeadTest < AcTest::Base
  def make_pi!(scene, name: 'pi')
    join_team!(make_user!(name: name), scene[:team])
  end

  def test_setting_pi_grants_project_head_on_the_project
    scene = build_scene!
    pi    = make_pi!(scene)
    exp   = make_experiment!(project: scene[:project], creator: scene[:creator])

    scene[:project].update!(supervised_by_id: pi.id)

    row = ua_for(scene[:project], pi)
    assert row, 'PI 应在项目上拿到一行'
    assert_equal 'project_head', row.user_role.name
    assert_equal 'manually', row.assigned
    assert_includes row.user_role.permissions, 'project_manage'
    assert can_read?(exp, pi), 'PI 应能看到项目下的实验'
  end

  def test_new_pi_can_manage_the_project
    scene = build_scene!
    pi    = make_pi!(scene)

    scene[:project].update!(supervised_by_id: pi.id)

    assert scene[:project].permission_granted?(pi, ProjectPermissions::MANAGE),
           'PI 应能管项目（原生不给，靠本 addon 补）'
  end

  def test_transferring_pi_revokes_the_old_pi_row
    scene = build_scene!
    pi1   = make_pi!(scene, name: 'pi1')
    pi2   = make_pi!(scene, name: 'pi2')
    scene[:project].update!(supervised_by_id: pi1.id)
    assert_equal 'project_head', ua_for(scene[:project], pi1).user_role.name, '前置：pi1 已是 PI'

    scene[:project].update!(supervised_by_id: pi2.id)

    assert_nil ua_for(scene[:project], pi1), '旧 PI 在本项目上的行应被收回'
    assert_equal 'project_head', ua_for(scene[:project], pi2)&.user_role&.name, '新 PI 应接上'
  end

  def test_old_pi_loses_descendant_visibility_after_transfer
    scene = build_scene!
    pi1   = make_pi!(scene, name: 'pi1')
    pi2   = make_pi!(scene, name: 'pi2')
    scene[:project].update!(supervised_by_id: pi1.id)
    exp   = make_experiment!(project: scene[:project], creator: scene[:creator])

    assert can_read?(exp, pi1), '前置：pi1 看得到实验'

    scene[:project].update!(supervised_by_id: pi2.id)

    refute can_read?(exp, pi1), '换人后旧 PI 不该再看见项目下的实验'
    assert can_read?(exp, pi2), '新 PI 应看得见'
  end

  def test_transfer_does_not_touch_the_creator_anchor
    scene = build_scene!
    pi    = make_pi!(scene)
    exp   = make_experiment!(project: scene[:project], creator: scene[:creator])
    scene[:project].update!(supervised_by_id: pi.id)

    row = ua_for(exp, scene[:creator])

    assert_equal 'experiment_owner', row.user_role.name,
                 '递归回收只删本钩子造的行，不能连 D3 的 creator 锚点一起删'
    assert can_read?(exp, scene[:creator])
  end
end
