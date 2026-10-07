# frozen_string_literal: true
#
# D9.1 安全护栏 —— revoke 只许动「PI 自己放的那一行」
#
# 这两条用例来自一次真实审计：原实现把「PI 勾过这一格」当成了**推断**——
#   UA 行 manually + 角色名不在 [experiment_owner, project_head] + 角色含 experiment_read
# 于是 `revoke_member_visibility` 写成了「扫 user_id + manually + 非系统角色，其余一律
# 打回 automatically」。任何**别的来源**在同一实验上留给该成员的手动行（宿主后台手工指派、
# 别的 addon）都会掉进去被静默降级 —— 而 `assigned: manually` 在原生语义里正是
# 「人工指定、不被自动机制覆盖」。原套件 53 条全绿，一条都没碰到这个口子。
#
# 现在「PI 勾过」有落点了（access_control_manual_grants），revoke 以它为准：
# 没有放行记录 → 一行 UA 都不碰。

require_relative 'test_helper'

class D99RevokeSafetyTest < AcTest::Base
  # 一个「别的来源」的角色：非系统角色、含 experiment_read（所以成员确实能读），
  # 又不是本 addon 的 WL 角色（WL 行是 revoke 该 destroy 的那一类）。
  OTHER_SOURCE_PERMISSIONS = %w[experiment_read experiment_read_canvas].freeze

  def setup_scene
    @scene  = build_scene!
    @exp    = make_experiment!(project: @scene[:project], creator: @scene[:creator])
    @member = add_restricted_member!(@scene[:project], @scene[:team], assigner: @scene[:creator])
    [@scene, @exp, @member]
  end

  # 在实验上给成员造一行「别的来源写的手动 UA」，返回那行。
  # 必须是 manually：非手动行本来就会被 job 覆盖，测不出误伤。
  def plant_foreign_manual_row!
    role = UserRole.create!(
      name: "other_source_#{SecureRandom.hex(4)}",
      permissions: OTHER_SOURCE_PERMISSIONS,
      predefined: false,
      created_by: AcTest.seed_admin!,
      last_modified_by: AcTest.seed_admin!
    )

    row = @exp.user_assignments.find_or_initialize_by(user: @member, team: @scene[:team])
    row.update!(user_role: role, assigned: :manually, assigned_by_id: @scene[:creator].id)
    [row, role]
  end

  def test_revoke_leaves_manual_rows_from_other_sources_alone
    setup_scene
    _row, role = plant_foreign_manual_row!

    assert can_read?(@exp, @member), '前置：这一行确实让成员读得到（否则测的不是这个口子）'

    result = revoke!(@exp, @member)

    assert_equal :noop, result, '这一格没有 PI 的放行记录，revoke 必须什么都不做'
    row = ua_for(@exp, @member)
    assert_equal 'manually', row.assigned, '别的来源写的 manually 不能被顺手打回 automatically'
    assert_equal role.id, row.user_role_id, '角色也不该被动'
    assert can_read?(@exp, @member), '成员的访问权不该被 revoke 拿走'
  end

  # PI 勾之前那行**本来就是 manually**（宿主手工指派的）→ 撤销时原样留着。
  # 这是上面那条的另一半：有了「放行记录」之后 revoke 会动手了，但仍要知道
  # 那行不是它翻的（was_manual），不能把宿主的授权当成自己的撤销。
  def test_revoke_keeps_a_preexisting_manual_marker
    setup_scene
    _row, role = plant_foreign_manual_row!

    assert grant!(@exp, @member), '前置：PI 放行这一格'

    result = revoke!(@exp, @member)

    row = ua_for(@exp, @member)
    assert_equal 'manually', row.assigned, '本来就是 manually 的行，撤销时不该被打回 automatically'
    assert_equal role.id, row.user_role_id, '角色也不该被降级'
    assert_equal :still_readable, result, '那行还在，成员仍可读 —— 界面要据此提示，别报假阴性'
  end

  # 对照组：PI 自己放的那一行（新建的 WL 行）必须被真的撤掉，
  # 否则护栏就把功能一起堵死了。
  def test_revoke_still_removes_the_row_the_pi_created
    setup_scene
    grant!(@exp, @member)
    assert can_read?(@exp, @member), '前置：放行后可见'

    assert_equal :revoked, revoke!(@exp, @member)

    refute can_read?(@exp, @member), 'PI 自己放的行必须能被收回'
    assert_equal false, cell(@scene[:project], @member, @exp)[:manual], '格子要回到虚框'
  end
end
