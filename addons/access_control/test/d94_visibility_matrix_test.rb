# frozen_string_literal: true
#
# D9.4 —— PI 可见性矩阵（成员 × 实验）
#
# 两个读数必须分开：visible（现在能不能读）与 manual（PI 是不是显式放过）。
# 只看 manual 会让 PI 以为勾了才生效（其实成员可能早就能读了）；
# 只看 visible 又会显示一堆 PI 从没开过的格子，矩阵失去意义。

require_relative 'test_helper'

class D94VisibilityMatrixTest < AcTest::Base
  def setup_scene
    @scene  = build_scene!
    @exp    = make_experiment!(project: @scene[:project], creator: @scene[:creator])
    @member = add_restricted_member!(@scene[:project], @scene[:team], assigner: @scene[:creator])
    [@scene, @exp, @member]
  end

  def test_matrix_lists_project_members_as_rows
    scene, = setup_scene

    ids = matrix(scene[:project])[:members].map { |m| m[:id] }

    assert_includes ids, scene[:creator].id, 'creator 应是一行'
    assert_includes ids, @member.id,         '受限成员也应是一行'
  end

  def test_restricted_member_cannot_read_experiment_before_grant
    setup_scene

    c = cell(@scene[:project], @member, @exp)

    assert_equal false, c[:visible], '受限成员放行了才应看得见'
    assert_equal false, c[:manual]
    refute can_read?(@exp, @member)
  end

  def test_visible_and_manual_are_reported_separately_for_creator
    setup_scene

    c = cell(@scene[:project], @scene[:creator], @exp)

    assert_equal true,  c[:visible], 'creator 当然看得见自己的实验（D3 锚点）'
    assert_equal false, c[:manual],  '但不是 PI 显式放行 —— 界面要画虚框而不是实心勾'
  end

  def test_grant_turns_both_visible_and_manual_true
    setup_scene

    assert grant!(@exp, @member), 'grant 应返回 true'

    c = cell(@scene[:project], @member, @exp)
    assert_equal true, c[:visible]
    assert_equal true, c[:manual], 'PI 显式放过，界面要画实心勾'
    assert can_read?(@exp, @member)
  end

  def test_grant_uses_the_whitelist_role_when_no_row_exists
    setup_scene
    grant!(@exp, @member)

    row = ua_for(@exp, @member)

    assert_equal 'WL-实验可见(含画布)', row.user_role.name
    assert_equal 'manually', row.assigned
  end

  def test_revoke_restores_invisibility
    setup_scene
    grant!(@exp, @member)
    assert can_read?(@exp, @member), '前置：放行后可见'

    revoke!(@exp, @member)

    refute can_read?(@exp, @member), '收回后应重新看不见'
    assert_equal false, cell(@scene[:project], @member, @exp)[:visible]
  end

  def test_grant_on_an_already_readable_row_only_marks_manual
    scene = build_scene!
    # 普通成员：项目下放的行本来就含 experiment_read，早就看得见
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator])
    exp    = make_experiment!(project: scene[:project], creator: scene[:creator])
    before = ua_for(exp, member)&.user_role

    assert can_read?(exp, member), '前置：普通成员本来就看得见'
    grant!(exp, member)

    row = ua_for(exp, member)
    assert_equal before&.id, row.user_role_id, 'grant 不许降级角色（会丢 experiment_users_manage 等权限）'
    assert_equal 'manually', row.assigned,      '只翻「PI 显式放过」这个标记'
  end

  def test_revoke_leaves_creator_anchor_untouched
    setup_scene
    grant!(@exp, @member)

    result = revoke!(@exp, @scene[:creator])

    # creator 的行是 D3 系统锚点（experiment_owner + manually），revoke 必须绕开
    assert_equal :noop, result
    assert can_read?(@exp, @scene[:creator]), 'creator 不应被 revoke 波及'
    assert_equal 'experiment_owner', ua_for(@exp, @scene[:creator]).user_role.name
  end
end
