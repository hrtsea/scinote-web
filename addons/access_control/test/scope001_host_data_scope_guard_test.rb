# frozen_string_literal: true
#
# SCOPE-001 第 0 步 —— 宿主数据权限（Scope）护栏
#
# ## 为什么必须先有这一份
# `app/models/concerns/permission_checkable_model.rb` 的
# `readable_by_user` / `with_granted_permissions` / `permission_granted?`
# 是本项目**所有数据权限的真相源头**，而 grep 显示它在 `spec/` 下**零覆盖**。
# 现状是 fail-open（忘写 scope = 静默返回全量），且已真实发生过漏写未被审查拦截。
# 在补护栏之前动任何重构代码都是盲改 —— 这份用例先把「当前正确行为」钉死，
# 第 3 步的 fail-closed 改造才有资格声称「没破坏」。
#
# ## 设计原则（重要，别改）
# **不复用预定义角色的权限清单。** owner/normal_user/... 的 `permissions`
# 会随宿主版本变化；若护栏依赖它，宿主一升级就是「假红」，更糟的是「假绿」。
# 所以这里全部用**最小精确权限集**自建角色：想要哪个位，就只给那个位。
#
# ## 对照身份
# 普通成员 / 队 owner / 跨组成员，外加「无任何指派」作 fail-open 反证。

require_relative 'test_helper'

class Scope001HostDataScopeGuardTest < AcTest::Base
  # ---------- 场景 ----------

  def setup_scene
    @scene   = build_scene!
    @team    = @scene[:team]
    @creator = @scene[:creator]
    @project = @scene[:project]
    @member  = join_team!(make_user!(name: 'member'), @team)
  end

  # ---------- 最小精确角色 ----------

  def make_role!(perms, prefix:)
    UserRole.create!(name: "SC-#{prefix}-#{SecureRandom.hex(6)}",
                     permissions: perms,
                     predefined: false,
                     created_by: AcTest.seed_admin!,
                     last_modified_by: AcTest.seed_admin!)
  end

  def project_read_role
    @project_read_role ||= make_role!([ProjectPermissions::READ], prefix: 'p-read')
  end

  # 「有指派但没读权限」的对照组：只给一个与读无关的权限位。
  # 用意是证明 UA 行哪怕描述了 phone role，缺 READ 位就等于看不见。
  def project_no_read_role
    @project_no_read_role ||= make_role!([ProjectPermissions::USERS_READ], prefix: 'p-noread')
  end

  def task_read_role
    @task_read_role ||= make_role!([MyModulePermissions::READ], prefix: 't-read')
  end

  # ---------- 三源指派各自独立构造 ----------

  def grant_ua!(obj, user, team, role)
    ua = obj.user_assignments.find_or_initialize_by(user: user, team: team)
    ua.update!(user_role: role, assigned: :manually)
    ua
  end

  def grant_ta!(obj, team, role)
    ta = obj.team_assignments.find_or_initialize_by(team: team)
    ta.update!(user_role: role)
    ta
  end

  def make_team_owner!(user, team)
    ua = UserAssignment.find_by!(assignable_type: 'Team',
                                 assignable_id: team.id,
                                 user_id: user.id)
    ua.update!(user_role: UserRole.find_predefined_owner_role)
  end

  def visible_project_ids(user)
    Project.readable_by_user(user).pluck(:id)
  end

  # ---------- 1. baseline：无指派 ⇒ 不可见 ----------

  def test_stranger_without_any_assignment_cannot_read
    setup_scene

    refute_includes visible_project_ids(@member), @project.id,
                    '无任何指派的成员必须不可见 —— 这是后面所有断言的 baseline，' \
                    '也是「漏写 scope 会返回全量」这个 fail-open 风险的反证'
  end

  # ---------- 2. direct UA：有无权限位的差别 ----------

  def test_direct_ua_with_read_bit_grants_visibility
    setup_scene
    grant_ua!(@project, @member, @team, project_read_role)

    assert_includes visible_project_ids(@member), @project.id
  end

  def test_direct_ua_without_read_bit_grants_nothing
    setup_scene
    grant_ua!(@project, @member, @team, project_no_read_role)

    refute_includes visible_project_ids(@member), @project.id,
                    '有 UA 行但角色不含 READ ⇒ 不可见。别被「他已经有一条指派」骗了'
  end

  # ---------- 3. ★ direct UA 排他遮蔽 team/group 指派 ----------

  def test_direct_ua_shadows_team_assignment
    setup_scene
    grant_ta!(@project, @team, project_read_role)
    assert_includes visible_project_ids(@member), @project.id, '前置：团队默认可见'

    grant_ua!(@project, @member, @team, project_no_read_role)

    refute_includes visible_project_ids(@member), @project.id,
                    '★ 排他遮蔽：个人被单独降级后，团队默认权限不再兜底。' \
                    '这条最容易坏 —— 朴素实现会把三源取 UNION 并集，' \
                    '导致「团队给读 + 个人禁读」被误判成可见'
  end

  # ---------- 4. TA：无任何 direct UA 时的团队默认 ----------

  def test_team_assignment_grants_every_team_member
    setup_scene
    grant_ta!(@project, @team, project_read_role)

    assert_includes visible_project_ids(@member), @project.id
  end

  # ---------- 5. team_id 是硬边界 ----------

  def test_cross_team_member_sees_nothing
    setup_scene
    grant_ua!(@project, @member, @team, project_read_role)
    assert_includes visible_project_ids(@member), @project.id, '前置：本队内可见'

    other_team = make_team!(creator: @creator)
    join_team!(@member, other_team)
    # 🔴 别用 @member.reload 切团队 —— 实测踩过：
    #   permission_team = @permission_team || current_team，前者是实例变量、
    #   后者是关联缓存。reload 之后 current_team_id 已经切成新 team，
    #   permission_team 却仍返回旧 team（本次诊断 35135 vs 35134）。
    #   ⇒ 必须 User.find 换一个全新的内存对象，否则会得到「假：跨队仍可见」。
    switched = User.find(@member.id)

    refute_includes visible_project_ids(switched), @project.id,
                    '切到别的 team 后必须看不见 —— 三源 scope 全带 team_id 过滤'
  end

  # 上面那条要穿过 user.permission_team 的缓存语义；这条直接测 scope 本身：
  # team_id 过滤以第二个参数显式传入，与「用户当前队伍」无关。
  def test_scope_filters_by_explicit_team_argument
    setup_scene
    grant_ua!(@project, @member, @team, project_read_role)
    other_team = make_team!(creator: @creator)

    assert_includes Project.readable_by_user(@member, @team).pluck(:id), @project.id

    refute_includes Project.readable_by_user(@member, other_team).pluck(:id), @project.id,
                    '显式传别的 team ⇒ 集合必须为空。team_id 必须在三条 UNION 分支里都过滤，' \
                    '漏一条就等于跨租户可见'
  end

  # ---------- 6. 实例版与 scope 版口径必须一致 ----------

  def test_instance_and_scope_agree_when_granted
    setup_scene
    grant_ua!(@project, @member, @team, project_read_role)

    assert @project.readable_by_user?(@member), '实例 permission_granted? 应为真'
    assert_includes visible_project_ids(@member), @project.id, 'scope readable_by_user 应为真'
  end

  def test_instance_and_scope_agree_when_denied
    setup_scene
    grant_ua!(@project, @member, @team, project_no_read_role)

    refute @project.readable_by_user?(@member), '实例 permission_granted? 应为假'
    refute_includes visible_project_ids(@member), @project.id, 'scope readable_by_user 应为假'
  end

  # ---------- 7. ★ 团队 Owner 不等于看见所有项目 ----------

  def test_team_owner_cannot_read_project_without_assignment
    setup_scene
    boss = join_team!(make_user!(name: 'boss'), @team)
    make_team_owner!(boss, @team)

    refute_includes visible_project_ids(boss), @project.id,
                    '★ permission_granted? 只查对象自身、绝不向上继承。' \
                    '所以「团队 Owner」推导不出「能看这个项目」—— 这就是 OPEN-L ' \
                    '那组归档 286 vs 3 分歧的根：manager 分支是显式绕过 readable，' \
                    '不是靠 owner 上卷。别指望 owner 自动可见'
  end

  # ---------- 8. top-level：creator 拿到 manually + Owner ----------

  def test_project_creator_gets_manual_owner_assignment
    setup_scene
    ua = UserAssignment.find_by(assignable_type: 'Project',
                                assignable_id: @project.id,
                                user_id: @creator.id)

    assert ua, 'Project 是 top_level_assignable ⇒ creator 应拿到一行'
    assert_equal 'manually', ua.assigned
    assert_equal UserRole.find_predefined_owner_role.id, ua.user_role_id
    assert_includes visible_project_ids(@creator), @project.id
  end

  # ---------- 9. 细粒度：同一对象上 READ 与 MANAGE 必须分流 ----------

  def test_task_read_does_not_imply_manage
    setup_scene
    experiment = make_experiment!(project: @project, creator: @creator)
    task       = make_task!(experiment: experiment, creator: @creator)
    grant_ua!(task, @member, @team, task_read_role)

    assert_includes MyModule.readable_by_user(@member).pluck(:id), task.id

    # ⚠ 原生拼写是 managable（permission_checkable_model.rb:39），不是 manageable
    refute_includes MyModule.managable_by_user(@member).pluck(:id), task.id,
                    'MyModule 有 33 个细粒度权限位，只读角色不能导出 manage'
  end
end
