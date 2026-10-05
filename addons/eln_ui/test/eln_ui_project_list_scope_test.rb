# frozen_string_literal: true
#
# ELN UI —— 项目列表 scope 单一真源（Scinote::ElnUi::ProjectListScope）的护栏（V1.27）
#
# 这个类存在的意义：让「项目列表页看到哪些项目」只有**一处**定义，被列表页 controller 与
# 工作台「参与项目」卡片共用 —— 好守住不变式「卡片数字 ≡ 点进去列表页筛出来的条数」。
#
# 本文件守两类断言（缺一不可，见 DESIGN-V1.27 §9.1）：
#   A. **等价断言（防分叉）**：for_listing 的产出必须等于「重构前 controller 的字面 scope 链」。
#      抓「有人把其中一侧绕开真源、自己又写了一遍」。对拍基准是**显式写出来的旧字面链**，
#      不是拿真源算真源（那不是循环论证）。
#   B. **真值断言（防口径错）**：在精确分布的夹具下，用手算期望钉死 scope 的边界：
#        参与 = 活动 ∩ 非模板（含 template=NULL） ∩ 可读 ∩ 成员；
#        负责 = supervised_by 或 **Project 级** Owner（多态表必须限承载面）。
#      抓「真源本身条件写错（少 .active / 漏 template[false,nil] / Owner 不限 assignable_type）」。
#
# ⚠ 空数据集陷阱：断言前一律先 refute_empty / refute_equal 0 守卫（本项目踩过 `[] == []` 假绿）。

require_relative 'test_helper'

class ElnUiProjectListScopeTest < AcTest::Base
  include Warden::Test::Helpers

  SCOPE = Scinote::ElnUi::ProjectListScope

  # ============================================================
  # A. 等价断言（防分叉）：for_listing ≡ 重构前的字面 scope 链
  # ============================================================
  def test_for_listing_equals_legacy_literal_scope_chain
    scene = build_scene!(visibility: :visible)
    team = scene[:team]
    user = scene[:creator]
    # 造多样本（含归档），避免 [] == [] 的空相等
    make_project!(team: team, creator: user)
    make_project!(team: team, creator: user)
    archived = make_project!(team: team, creator: user)
    archived.update!(archived: true)

    got = SCOPE.for_listing(team: team, user: user, view_mode: 'active').pluck(:id).sort
    want = legacy_active_scope(team, user).pluck(:id).sort

    refute_empty want, '基准集合不能为空（防空断言）'
    assert_equal want, got,
                 'ProjectListScope.for_listing 必须与重构前的字面 scope 链**同 id 集合**'
  end

  # ============================================================
  # B. 真值断言（防口径错）
  # ============================================================

  # template 是**可空布尔**（生产 159 行里 158 行 NULL）：NULL 表示「不是模板」，必须收进来。
  # 写 where(template: false) 会把这 158 行全排掉 → 列表恒空。这条直接挡住 RC-2。
  def test_template_null_projects_are_included
    scene = build_scene!(visibility: :visible)
    team = scene[:team]
    user = scene[:creator]
    project = make_project!(team: team, creator: user)
    assert_nil project.reload.template, '前提：template 为 NULL（生产主态）'

    ids = SCOPE.for_listing(team: team, user: user).pluck(:id)

    refute_empty ids, '集合不能为空（防空断言）'
    assert_includes ids, project.id, 'template=NULL 的项目必须被收进来（写 template: false 会排掉）'
  end

  # 归档项目不出现在活动视图、必须出现在归档视图。这条直接挡住 RC-3（少 .active/.archived）。
  def test_archived_projects_excluded_from_active_and_present_in_archived
    scene = build_scene!(visibility: :visible)
    team = scene[:team]
    user = scene[:creator]
    project = make_project!(team: team, creator: user)
    project.update!(archived: true)

    active_ids = SCOPE.for_listing(team: team, user: user, view_mode: 'active').pluck(:id)
    archived_ids = SCOPE.for_listing(team: team, user: user, view_mode: 'archived').pluck(:id)

    refute_empty archived_ids, '归档视图不应为空（防空断言）'
    refute_includes active_ids, project.id, '归档项目不能出现在活动视图'
    assert_includes archived_ids, project.id, '归档项目必须出现在归档视图'
  end

  # 参与真值表：手算口径（不是由实现反推）。
  #   参与 = 活动 ∩ 非模板（含 NULL） ∩ 可读 ∩ **成员**；可读但非成员**不算**。
  def test_participation_truth_table
    scene = build_scene!(visibility: :visible)
    team = scene[:team]
    user = scene[:creator]

    # a、b：参与且活动 → 计入
    make_project!(team: team, creator: user)
    make_project!(team: team, creator: user)
    # c：参与但归档 → 活动视图不计
    archived = make_project!(team: team, creator: user)
    archived.update!(archived: true)
    # d：参与但模板（template=true）→ 不计
    template = make_project!(team: team, creator: user)
    template.update!(template: true)
    # e：模板列 NULL（生产主态）且参与 → 必须计入
    null_template = make_project!(team: team, creator: user)
    assert_nil null_template.reload.template, '前提：e 的 template 为 NULL'
    # f：可读但**非成员** → 不计
    foreign = foreign_readable_project!(team: team)
    assert foreign.readable_by_user?(user), '前提：foreign 对 user 可读'
    assert_nil ua_for(foreign, user), '前提：foreign 不是 user 的成员'

    r = SCOPE.participation(team: team, user: user)

    refute_equal 0, r[:participated], '数据集非空（防空断言）'
    # 手算：scene 项目 + a + b + e = 4（c 归档 / d 模板 / f 非成员 排除）
    assert_equal 4, r[:participated],
                 '手算：scene、a、b、e 四条（排除 归档/模板/可读非成员）'
  end

  # 负责真值表（双轨）：Project 级 Owner 或 supervised_by 命中即算；**非** Project 级 Owner 不算。
  # 这条挡住 RC-4（多态表不限承载面）。
  def test_responsible_requires_project_level_owner_or_supervisor
    scene = build_scene!(visibility: :visible)
    team = scene[:team]
    owner = scene[:creator]                       # 建项目的人 → Project 级 Owner
    plain = join_team!(make_user!(name: 'scope-plain'), team)

    # P：owner 是 Project 级 Owner（负责）；plain 是普通成员（参与但不负责）
    project = make_project!(team: team, creator: owner)
    add_project_member!(project, plain, team, role: 'User')

    assert_equal 1, SCOPE.participated(team: team, user: plain).distinct.count(:id),
                 '前提：plain 参与 P'
    assert_equal 0, SCOPE.participation(team: team, user: plain)[:responsible],
                 '非 Owner 成员不得被判为负责'

    # owner 负责 P（Project 级 Owner 轨）
    assert_includes responsible_ids(owner), project.id, 'Project 级 Owner 必须负责'
    # supervised_by 轨：把 P 的 supervised_by 设为 plain → plain 负责
    project.update_column(:supervised_by_id, plain.id)
    assert_includes responsible_ids(plain), project.id, 'supervised_by 命中即负责'
    project.update_column(:supervised_by_id, nil)

    # 🔴 RC-4 对拍：给 plain 造一条**非 Project 级**（Experiment）Owner UA，其 assignable_id
    #   恰等于 project.id。正确实现（responsible_condition 限 assignable_type='Project'）
    #   → plain 仍不负责；若删掉 assignable_type 条件 → 这条 Experiment 级 Owner 命中
    #   project.id → plain 被误判负责 → 本用例红。
    insert_foreign_owner_assignment!(user: plain, team: team,
                                     assignable_id: project.id,
                                     assignable_type: 'Experiment')

    assert_equal 0, SCOPE.participation(team: team, user: plain)[:responsible],
                 '非 Project 级 Owner 不得让项目变成「我负责」（多态表必须限承载面）'
  end

  # ============================================================
  # 深链筛选条件契约（OPEN-WB-DRILL-8）：initialFilters 归一化后下发
  # ============================================================
  def test_initial_filters_are_normalized_with_numeric_member_ids
    scene = build_scene!(visibility: :visible)
    user = scene[:creator]

    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.get('/eln_project_list',
                params: { filters: { members: [user.id] }, view_mode: 'active', format: :json })
    assert_equal 200, session.response.status, 'json 出口必须可用'

    body = JSON.parse(session.response.body)
    filters = body['initialFilters']
    refute_nil filters, 'payload 必须下发 initialFilters（供前端深链回填 ui.filters）'
    # ⚠ 类型归一：URL 里 "35" 是字符串，必须回成 Integer（对齐真机 <option :value="m.id">）
    assert_equal [user.id], filters['members'],
                 'initialFilters.members 必须是数字 id 数组（类型归一，否则多选框回填后不选中）'
    assert_instance_of Integer, filters['members'].first
    assert_equal 'active', body['viewMode'], 'viewMode 必须与 URL 一致'
  end

  private

  # 重构**前** `ProjectListController#scoped_projects`（L190-197）的**字面** scope 链 ——
  # 作为等价断言的对拍基准（不是拿真源算真源）。
  def legacy_active_scope(team, user)
    Project.where(team_id: team.id, template: [false, nil])
           .distinct
           .readable_by_user(user)
           .active
  end

  # 某用户「负责」的项目 id 集合（用于断言 responsible_condition 的产物）。
  def responsible_ids(user)
    Project.where(SCOPE.responsible_condition(user)).pluck(:id)
  end

  # 造一个「别人建、给全队只读」的项目：被考察用户对它可读（TeamAssignment 携带
  # project_read → 命中 readable_by_user 的 team_assignments 分支），但没有 Project 级 UA。
  def foreign_readable_project!(team:)
    stranger = join_team!(make_user!(name: 'scope-stranger'), team)
    project = make_project!(team: team, creator: stranger)
    ::TeamAssignment.create!(assignable: project, team: team,
                             user_role: ::UserRole.find_predefined_normal_user_role,
                             assigned: :manually)
    project
  end

  # 给**指定用户**在项目上落一条 Project 级 UA（成员）。
  # ⚠ 不能用 AcTest::Base#add_member! —— 它会**新建**一个用户，而这里要挂的正是
  #   已有的 plain；也不需要 PropagateAssignmentJob（readable_by_user? 只看 Project 级 UA）。
  def add_project_member!(project, user, team, role: 'User')
    ua = project.user_assignments.find_or_initialize_by(user: user, team: team)
    ua.user_role ||= ::UserRole.find_by(name: role) || ::UserRole.find_predefined_normal_user_role
    ua.assigned = :manually
    ua.assigned_by ||= user
    ua.save!
    ua
  end

  # 直插一条**非 Project 级**的 UserAssignment（绕开 AR 回调/校验）。
  #   ⚠ 必须 insert_all!，不能 create!：UserAssignment 的 before_validation
  #     `set_assignable_team` 会调 `assignable.team`，而这里 assignable_type 是伪造的
  #     （Experiment 却用 project id），load 出来是别的对象 → create! 直接炸。
  #   ⚠ assigned 是 NOT NULL enum，显式给 1（manually）。
  def insert_foreign_owner_assignment!(user:, team:, assignable_id:, assignable_type:)
    role = UserRole.find_predefined_owner_role
    raise '前提：Owner 预定义角色不存在' if role.nil?

    now = Time.current
    ::UserAssignment.insert_all!([
                                   { user_id: user.id, assignable_type: assignable_type,
                                     assignable_id: assignable_id, user_role_id: role.id,
                                     team_id: team.id, assigned: 1,
                                     created_at: now, updated_at: now }
                                 ])
  end
end
