# frozen_string_literal: true
#
# 工作台（Workbench）—— 六块数据装配（REQ-DASHBOARD）
#
# 守 4 件事（都是「不许编」的铁律落点）：
#   1. meta.greeting / role / notice 全部来自真源（User 真名 / UserRole —— **按承载面分级**：
#      Team 级 Owner → 单位管理员；Project 级 Owner 或 supervised_by → 项目负责人 /
#      原生 Notification 未读数），不落演示文案；
#   2. dist 用**数据库里真实的 MyModuleStatus 名 + 真色**（不是原型的五个演示标签）；
#   3. groups / dist 无数据时给**空数组 / '—'**，绝不回落「张负责人」「82%」这类画布值；
#   4. entries[].to 全部来自宿主路由表真实 helper（前端不写死宿主路由）。
#
# ⚠ 本文件所有 `def test_*` 必须留在文件末尾的 `private` **之前**，
#   否则 minitest 静默不执行（runs 数不动就是报警）。

require_relative 'test_helper'

class WorkbenchTest < AcTest::Base
  include Warden::Test::Helpers

  # ============================================================
  # meta：页头 / 角色徽章 / 通知栏
  # ============================================================

  # ① 问候语 = 时段 + 用户真名（不含原型的「张负责人」演出值）
  def test_meta_greeting_uses_real_user_full_name
    scene = build_scene!

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    greeting = body[:meta][:greeting]
    refute_nil greeting, '问候语必须有值'
    assert_includes greeting, scene[:creator].full_name, '问候语必须带用户真名'
    assert_match(/^(凌晨|上午|下午|晚上)好，/, greeting, '问候语必须是「时段好，真名」形状')
  end

  # ② 普通组员：非 Team 级 Owner、也非任何可读 project 的负责人 → 「普通组员」
  #    ⚠ 2026-10-04 QA 修：原用例先 make_owner_assignment! 再断言「普通组员」，
  #      与 payload 的判定优先级（①单位管理员 ②项目负责人 ③普通组员）自相矛盾
  #      → 实际拿到「单位管理员 · Owner」。这里不再挂 Owner 赋值。
  def test_role_is_plain_member_for_plain_user
    scene = build_scene!
    strip_owner!(scene[:creator])

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal '普通组员', body[:meta][:role]
  end

  # ③ 单位管理员：**Team 级**（单位级）宿主 UserRole = Owner（只认 name，不认 id）
  #    ⚠ 承载面是这条用例的关键：`make_owner_assignment!` 造的是 Team 级赋值。
  #      原实现不限 assignable_type，但这里恰好只造 Team 级 ——
  #      所以源码的宽口径**从未被这条用例触发**，见下面 ③-b 补的那层覆盖。
  def test_role_is_admin_when_owner_assignment_exists
    scene = build_scene!
    make_owner_assignment!(user: scene[:creator], team: scene[:team])

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal '单位管理员 · Owner', body[:meta][:role]
  end

  # ③-b 🔴 护栏：Project 级 Owner **不是**单位管理员
  #
  # 这是原实现的真实事故形态：`owner_user?` 不限 assignable_type →
  # 「在某个 Project / Experiment / MyModule 上挂着 Owner」也被算成单位管理员。
  # 生产实测（4 个用户的库）：**3 个**被贴成「单位管理员 · Owner」，而全库 Team 级 Owner 只有 1 条。
  # 受害样本 hrtsea@qq.com：Team 级角色是 `User`，Owner 命中全是
  # {Experiment: 96, MyModule: 50, Project: 4} —— 他其实是 203 个项目的负责人。
  #
  # ⚠ 必须先把 **Team 级** Owner 清掉：否则「Team 级命中」与「Project 级误命中」
  #   两种成因同时为真，用例测不出是哪一条导致的。
  def test_role_is_not_admin_for_project_level_owner_only
    scene = build_scene!(visibility: :visible)
    project = make_project!(team: scene[:team], creator: scene[:creator], visibility: :visible)
    strip_owner!(scene[:creator])
    ensure_team_member!(scene[:creator], scene[:team], role: 'User')
    make_owner_assignment!(user: scene[:creator], team: scene[:team], assignable: project)

    # 前提守卫①：Team 级必须没有 Owner —— 否则测不出「Project Owner 被误算」
    assert_equal false, team_owner_assignment?(scene[:creator], scene[:team]),
                 '前提守卫失败：Team 级仍有 Owner 赋值，两种成因混在一起'
    # 前提守卫②：Project 级 Owner 必须真的挂上 —— 否则断言恒真（空断言）
    assert_equal true, project_owner_assignment?(scene[:creator], project),
                 '前提守卫失败：Project 级 Owner 没挂上，用例退化成空断言'

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    refute_equal '单位管理员 · Owner', body[:meta][:role],
                 'Project 级 Owner 被误判成单位管理员 —— 角色判定没限定 assignable_type'
    assert_equal '项目负责人', body[:meta][:role],
                 'Project 级 Owner 应落入「项目负责人」（OPEN-1 双轨：supervised_by 或 Project Owner）'
  end

  # ④ 项目负责人：任一**可读** project 的 supervised_by 是自己
  #    （宽口径，OPEN-1 未决前不收窄）
  #
  # ⚠ 语句顺序（2026-10-05 修，别再改回来）：
  #     supervised_by 赋值 → **strip_owner!** → 以**非 Owner 角色**建可读
  #   `strip_owner!` 删的是「带 Owner 角色的 UserAssignment」，
  #   而 `allow_project_read!` 建的那条**本身也是一条 UA**：
  #     · strip 放最后 → 把刚建的可读赋值一起删掉 → 项目不再 readable
  #       → project_lead? 落空 → 判成「普通组员」（本用例曾经假红的根因）；
  #     · strip 放最前但用默认(Owner) 角色建可读 → strip 白清 → team_admin? 又命中。
  #   所以顺序是「先清、后建」，并且**必须显式传 role: 'User'**。
  def test_role_is_project_lead_when_supervising_readable_project
    # ⚠ 必须是 visible 项目：build_scene! 默认 visibility=:hidden，
    #   hidden 项目不进 Project.readable_by_user → project_lead? 落空 → 判成普通组员。
    scene = build_scene!(visibility: :visible)
    project = make_project!(team: scene[:team], creator: scene[:creator], visibility: :visible)
    project.update_column(:supervised_by_id, scene[:creator].id)
    strip_owner!(scene[:creator])
    # 清 Owner（免 team_admin? 误命中）之后，必须把「人是这个队成员」接回来：
    # strip_owner! 删的是**带 Owner 角色的 UA**，Team 级那条也在里面 ——
    # 删完 user.permission_team 变 nil，而 readable_by_user? 是 **team 作用域**
    # （permission_checkable_model.rb#permission_granted?），前提没了 → 后面白建。
    ensure_team_member!(scene[:creator], scene[:team], role: 'User')
    # 再以非 Owner 角色建可读（保住 readable_by_user? 这个前提）
    allow_project_read!(project, scene[:creator], role: 'User')

    # 前提守卫①：Owner 必须真的清干净。
    #   team_admin? 优先级高于 project_lead?，**任意层级**的 Owner 残留都可能让
    #   role_value 提前返回「单位管理员 · Owner」，把「项目负责人」这条断言掩盖掉。
    #   ⚠ 口径收窄（2026-10-05）后 team_admin? 只认 Team 级，但本守卫仍按
    #     「任意层级 Owner = 0」来要求 —— 更严不会错，宽了才会漏。
    still_owner = ::UserAssignment.joins(:user_role)
                                  .where(user_id: scene[:creator].id, user_roles: { name: 'Owner' })
                                  .exists?
    assert_equal false, still_owner,
                 '前提守卫失败：Owner 赋值未清干净，不能直接断言项目负责人'

    # 前提守卫②（新增）：strip_owner! 不许把「项目可读」这个前提也带走 ——
    # 少了这条，守卫①通过 + 业务断言假红 就是同一前提同时造出「假绿 + 假红」的经典坑。
    # ⚠ 消息里带上诊断（project 的 visibility、角色权限、UA 清单）：
    #    readable_by_user? 是 **team 作用域**（permission_checkable_model.rb#permission_granted?
    #    按 user.permission_team 查），这条断言一挂，
    #    光看「不可读」三字查不出是谁把「人在队里 / 角色有 project_read」这个前提弄没了。
    ua_desc = ::UserAssignment.where(user_id: scene[:creator].id).map do |a|
      "#{a.assignable_type}##{a.assignable_id}/#{a.user_role&.name.inspect}"
    end
    assert project.readable_by_user?(scene[:creator]),
           "前提守卫失败：项目已不可读（project_lead? 会落空）—— " \
           "visibility=#{project.visibility.inspect} " \
           "role=#{(::UserRole.find_by(name: 'User')&.permissions.to_a & ['project_read']).inspect} " \
           "ua=#{ua_desc.inspect}"

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal '项目负责人', body[:meta][:role]
  end

  # ⑤ 通知栏：0 条未读 → 「暂无未读通知」（状态描述，不是演示文案）
  def test_notice_reports_empty_state_when_no_unread
    scene = build_scene!
    allow_project_read!(readable_project(scene), scene[:creator])

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal '暂无未读通知', body[:meta][:notice]
  end

  # ⑥ 通知栏：有未读 → 「N 条未读通知」（只有条数，不编触发源细目 —— OPEN-WB-2）
  def test_notice_reports_real_unread_count
    scene = build_scene!
    user = scene[:creator]
    allow_project_read!(readable_project(scene), user)
    # ⚠ 先把本人历史未读清干净，再放 1 条，断言才不会被别的用例漏进来的行打扰
    ::Notification.where(recipient_type: 'User', recipient_id: user.id, read_at: nil).delete_all
    ::Notification.create!(type: 'GeneralNotification', recipient: user, params: {})
    expected = ::Notification.where(recipient_type: 'User', recipient_id: user.id, read_at: nil).count

    body = Scinote::Workbench::WorkbenchPayload.call(user: user, team: scene[:team])

    assert_equal "#{expected} 条未读通知", body[:meta][:notice]
    assert_operator expected, :>=, 1, '用例必须真的造出 1 条未读，否则这条断言是空断言'
  end

  # ⑦ 状态机说明：下发数据库真实状态名，不是原型的五个演示标签
  def test_meta_status_machine_lists_real_status_names
    scene = build_scene!
    status = make_status!(name: 'WB-实测状态')

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_includes body[:meta][:statusMachine], status.name
  end

  # ============================================================
  # dist：任务状态分布（真状态名 + 真色）
  # ============================================================

  # ① 分组取的是 my_module_statuses 里的真名 + 真色
  def test_dist_uses_real_database_status_names_and_colors
    scene = build_scene!
    user = scene[:creator]
    project = readable_project(scene)
    allow_project_read!(project, user)
    status = make_status!(name: 'WB-进行中', color: '#3070ED')
    exp = make_experiment!(project: project, creator: user)
    mod = make_task!(experiment: exp, creator: user)
    mod.update!(my_module_status: status)
    allow_task_read!(mod, user)

    body = Scinote::Workbench::WorkbenchPayload.call(user: user, team: scene[:team])

    dist = body[:dist]
    refute_nil dist, 'dist 必须有值'
    assert_equal 1, dist.size, '一个真实状态 → 一行'
    assert_equal 'WB-进行中', dist.first[:label], '标签必须是数据库里的状态名'
    assert_equal 1, dist.first[:num]
    assert_equal '#3070ED', dist.first[:color], '色值由 payload 下发，不能组件硬编'
  end

  # ② 无任务 → 空数组（绝不回落演示标签）
  def test_dist_is_empty_array_when_team_has_no_modules
    scene = build_scene!

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal [], body[:dist], '无真实状态数据 → 空数组'
  end

  # ============================================================
  # groups：小组汇总
  # ============================================================

  # ① 小组为空 → 空数组（不回落「一组 · 增韧体系」）
  def test_groups_is_empty_array_when_team_has_no_user_groups
    scene = build_scene!

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal [], body[:groups], '无小组 → 空数组'
  end

  # ② 有小组但组员没有任务 → 行存在，组长 '—'、完成率 '—'、不带 tone
  def test_group_row_shows_dash_when_group_has_no_tasks
    scene = build_scene!
    group = make_user_group!(team: scene[:team], name: 'WB-测试小组')
    allow_project_read!(readable_project(scene), scene[:creator])

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal ['WB-测试小组'], body[:groups].map { |g| g[:name] }
    row = body[:groups].first
    assert_equal '—', row[:leader], 'UserGroup 无 leader 承载列 → 显式留白（OPEN-WB-1）'
    assert_equal '—', row[:rate], '无任务 → 完成率留白，不编百分比'
    assert_nil row[:tone], '无完成率 → 不给 tone'
  end

  # ③ 完成率是真的：终态任务占多数 → done
  def test_group_rate_reflects_real_completion_ratio
    scene = build_scene!
    user = scene[:creator]
    project = readable_project(scene)
    allow_project_read!(project, user)
    group = make_user_group!(team: scene[:team], name: 'WB-测试小组')
    ::UserGroupMembership.create!(user_group: group, user: user, created_by: user)
    final_status = final_status!
    exp = make_experiment!(project: project, creator: user)
    done_mod = make_task!(experiment: exp, creator: user)
    done_mod.update_column(:my_module_status_id, final_status.id)
    allow_task_read!(done_mod, user)
    open_mod = make_task!(experiment: exp, creator: user)
    open_mod.update_column(:my_module_status_id, make_status!(name: 'WB-未开始').id)
    allow_task_read!(open_mod, user)

    body = Scinote::Workbench::WorkbenchPayload.call(user: user, team: scene[:team])

    row = body[:groups].find { |g| g[:name] == 'WB-测试小组' }
    refute_nil row, '小组行必须存在'
    assert_equal '50%', row[:rate], '1/2 完成 → 50%（真算，不写死）'
    assert_equal 'warn', row[:tone], '50% < 80% → warn'
  end

  # ============================================================
  # kpis
  # ============================================================

  # ① 小组数 = team.user_groups.count，trend 覆盖组员真数
  def test_groups_kpi_counts_real_user_groups_and_members
    scene = build_scene!
    group = make_user_group!(team: scene[:team], name: 'WB-测试小组')
    ::UserGroupMembership.create!(user_group: group, user: scene[:creator], created_by: scene[:creator])
    allow_project_read!(readable_project(scene), scene[:creator])

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    kpi = body[:kpis].find { |k| k[:label] == '小组数' }
    refute_nil kpi, '小组数 KPI 必须存在'
    assert_equal '1', kpi[:value]
    assert_includes kpi[:trend], '覆盖 1 名组员'
  end

  # ② 云版 Token 卡在私有化部署不输出（spec 只在云版要求 Token 项）
  def test_token_kpi_card_is_not_emitted
    scene = build_scene!

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    refute body[:kpis].any? { |k| k[:label].include?('Token') }, '私有化部署不输出 Token 卡'
  end

  # ③ 项目花费 = 消耗明细聚合（带符号求和：还回是负数）
  def test_cost_kpi_sums_consume_records
    scene = build_scene!
    user = scene[:creator]
    project = readable_project(scene)
    allow_project_read!(project, user)
    # ⚠ 2026-10-04 QA 修：occurred_at / source_type 都是 NOT NULL，
    #   原工厂只给 6 个字段 → PG::NotNullViolation。
    Scinote::ElnUi::ConsumeRecord.create!(
      kind: 'material', name: 'WB-基料', quantity: 10.to_d, unit: 'kg',
      unit_price: 30.to_d, amount: 300.to_d, project: project, user: user,
      occurred_at: Time.current, source_type: 'RepositoryLedgerRecord', source_id: 0
    )

    body = Scinote::Workbench::WorkbenchPayload.call(user: user, team: scene[:team])

    kpi = body[:kpis].find { |k| k[:label] == '项目总花费' }
    refute_nil kpi, '花费 KPI 必须存在'
    assert_equal '¥300', kpi[:value]
    assert_includes kpi[:trend], '材料 100%'
  end

  # ============================================================
  # todos
  # ============================================================

  # ① 他人的待审申请进待办；**自己提的不进**（审批口径与 Workflow 同源宽口径）
  def test_todos_exclude_own_resource_applications
    scene = build_scene!
    user = scene[:creator]
    other = make_user!(name: 'wb-other')
    project = readable_project(scene)
    allow_project_read!(project, user)
    mine = make_resource_application!(project: project, requestor: user, status: 'submitted')
    theirs = make_resource_application!(project: project, requestor: other, status: 'submitted')

    body = Scinote::Workbench::WorkbenchPayload.call(user: user, team: scene[:team])

    # ⚠ 2026-10-04 QA 修：payload 的 title 是「<物料名>（<编号>）」形状，
    #   直接拿裸编号断言必然不 include —— 改成「标题里含编号」判定。
    titles = body[:todos].map { |t| t[:title] }
    assert titles.any? { |t| t.include?(theirs.no) },
           "他人提交的待审申请要进「待我审」：titles=#{titles.inspect}"
    assert titles.none? { |t| t.include?(mine.no) },
           "自己提的申请不进「待我审」：titles=#{titles.inspect}"
  end

  # ② 我的任务进待办；due 无真源写 '—'（不编日期）
  def test_todo_for_my_assigned_module_and_dash_when_no_due_date
    scene = build_scene!
    user = scene[:creator]
    project = readable_project(scene)
    allow_project_read!(project, user)
    exp = make_experiment!(project: project, creator: user)
    mod = make_task!(experiment: exp, creator: user)
    allow_task_read!(mod, user)
    ua = ua_for(mod, user)
    refute_nil ua, '任务必须有 UserAssignment 才能算「我的任务」'

    body = Scinote::Workbench::WorkbenchPayload.call(user: user, team: scene[:team])

    todo = body[:todos].find { |t| t[:title] == mod.name }
    refute_nil todo, '被指派的任务必须出现在待办里'
    assert_equal '任务', todo[:type]
    assert_equal '—', todo[:due], 'due_date 无值 → 显式留白，不编日期'
    refute_nil todo[:status]
  end

  # ============================================================
  # entries：链接必须来自真实宿主路由（前端不写死宿主路由）
  # ============================================================

  def test_entries_to_come_from_real_host_routes
    scene = build_scene!
    allow_project_read!(readable_project(scene), scene[:creator])

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    entries = body[:entries]
    refute_nil entries, 'entries 必须有值'
    entries.each do |e|
      refute_nil e[:to]
      assert e[:to].to_s.start_with?('/'), "宿主路由必须以 / 开头：#{e[:label]} -> #{e[:to]}"
    end
    assert_includes entries.map { |e| e[:to] },
                    '/eln_project_list', '项目管理指向宿主真实列表页'
  end

  # 原型的「新建实验任务 / 报表中心」宿主无承载面 → 不输出（显式留白）
  def test_unsupported_prototype_entries_are_not_emitted
    scene = build_scene!

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    labels = body[:entries].map { |e| e[:label] }
    refute_includes labels, '新建实验任务', '宿主无承载面 → 不输出'
    refute_includes labels, '报表中心', '宿主无承载面 → 不输出'
  end

  # 六块齐全（前端只读这六个 key）
  def test_payload_exposes_exactly_the_six_defined_blocks
    scene = build_scene!
    allow_project_read!(readable_project(scene), scene[:creator])

    body = Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal %i[meta kpis todos dist groups entries], body.keys
  end

  # ============================================================
  # 完成率基准：final_status_ids 的批量取法必须等价于逐条 final_status?
  # ============================================================

  # payload 为了不再每条状态问两次 ORM，改成按 **flow** 批量取终态。
  #   ⚠ 这条用例锁的是「口径不变」—— 有人再把它下推成「id 不在任何 previous_status_id 里」
  #     那种 SQL 会立刻红：同一 flow 里允许挂多条互不相连的状态（本文件 make_status! 就这么造），
  #     「没有后继」的状态不止一个，而 flow.final_status 只认其中一条 → 完成率被算高。
  def test_final_status_ids_matches_native_predicate
    make_status!(name: 'WB-终态基准') if ::MyModuleStatus.unscoped.count.zero?

    ruby_ids = ::MyModuleStatus.unscoped.select(&:final_status?).map(&:id).uniq.sort
    batched_ids = ::Scinote::Workbench::WorkbenchPayload.new(user: nil, team: nil)
                                                        .send(:final_status_ids).sort

    refute_empty ruby_ids, '至少得有一个真终态，否则这条断言是空断言'
    assert_equal ruby_ids, batched_ids, 'final_status_ids 的批量取法与逐条 final_status? 不一致'
  end

  # ============================================================
  # 私有工厂（只在这里被上面的用例调用）
  # ============================================================

  private

  def payload_for(scene)
    Scinote::Workbench::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])
  end

  # build_scene! 建的 project 未必对 creator 可读 —— 工作台口径是「可读 project」，
  # 所以显式补一条可读赋值，避免用例因为「读不到」而全部假红。
  def readable_project(scene)
    project = make_project!(team: scene[:team], creator: scene[:creator])
    allow_project_read!(project, scene[:creator])
    project
  end

  # role: 传名字则**显式用该角色**（例如 'User'，用来做「非 Owner 的可读」）；
  #       不传则沿用原来的默认取角色逻辑。
  def allow_project_read!(project, user, role: nil)
    return if project.readable_by_user?(user)

    ua = ::UserAssignment.find_or_initialize_by(assignable: project, user: user, team: project.team)
    ua.user_role ||= role ? UserRole.find_by(name: role)
                          : read_role!(project)
    ua.assigned_by ||= user
    ua.assigned ||= assigned_flag
    ua.save!
  end

  # strip_owner! 删的是「带 Owner 角色的 UA」，Team 级那条也在其中 ——
  # 删完 user.permission_team 变 nil，而 readable_by_user? 是 team 作用域
  # （permission_granted? 先按 (user, permission_team) 查 UA，命中不了就直接落空），
  # 于是后面再怎么建项目级 UA 都白搭。所以 strip 之后要把「人是队成员」接回来，
  # 用**非 Owner** 角色（否则 strip 白清，team_admin? 又命中）。
  def ensure_team_member!(user, team, role: 'User')
    role_obj = ::UserRole.find_by(name: role)
    raise "角色 #{role} 不存在（用例前提）" if role_obj.nil?

    ua = ::UserAssignment.find_or_initialize_by(assignable: team, user: user, team: team)
    ua.user_role ||= role_obj
    ua.assigned_by ||= user
    ua.assigned ||= assigned_flag
    ua.save!
    ua
  end

  def allow_task_read!(mod, user)
    ua = ::UserAssignment.find_or_initialize_by(assignable: mod, user: user, team: mod.experiment.project.team)
    ua.user_role ||= read_role!(mod)
    ua.assigned_by ||= user
    ua.assigned ||= assigned_flag
    ua.save!
  end

  # user_role 不能为 nil（否则 UserAssignment 校验挂 → 整条用例假红）
  def read_role!(_obj)
    UserRole.where.not(name: 'Owner').order(:id).first || make_role!(name: 'WB-reader')
  end

  def assigned_flag
    defined = UserAssignment.defined_enums['assigned']
    defined && defined['manually_assigned'] || 1
  end

  def make_role!(name:)
    role = UserRole.new(name: name)
    role.predefined = name if UserRole.column_names.include?('predefined')
    role.save!
    role
  end

  # UserRole 真名是 Owner / User / Technician / Viewer —— 只认 name，不认 id
  def owner_role!
    role = UserRole.find_by(name: 'Owner')
    return role if role

    role = UserRole.new(name: 'Owner')
    role.predefined = 'Owner' if UserRole.column_names.include?('predefined')
    role.save!
    role
  end

  # 造一条 Owner 赋值。
  #   assignable 默认 **team** —— 这是「单位管理员」的正确承载面（Team 级）。
  #   ⚠ 传 project 会造出「**项目级** Owner」，那是**项目负责人**不是单位管理员 ——
  #     UserAssignment 是多态表，同一条 SQL 换个 assignable_type 就是另一个层级的角色。
  #     见 test_role_is_not_admin_for_project_level_owner_only。
  def make_owner_assignment!(user:, team:, assignable: nil)
    target = assignable || team
    role = owner_role!
    ua = ::UserAssignment.find_by(user_id: user.id,
                                  assignable_type: target.class.name,
                                  assignable_id: target.id)
    if ua
      ua.update!(user_role: role)
    else
      ::UserAssignment.create!(user: user, assignable: target, user_role: role,
                               assigned_by: user, team: team, assigned: assigned_flag)
    end
  end

  # ---- 承载面守卫（用例自己的前提校验，不是业务断言）----

  def team_owner_assignment?(user, team)
    ::UserAssignment.where(user_id: user.id, assignable_type: 'Team', assignable_id: team.id)
                    .joins(:user_role).where(user_roles: { name: 'Owner' }).exists?
  end

  def project_owner_assignment?(user, project)
    ::UserAssignment.where(user_id: user.id, assignable_type: 'Project', assignable_id: project.id)
                    .joins(:user_role).where(user_roles: { name: 'Owner' }).exists?
  end

  # ⚠ MyModuleStatus 是原生动态状态流（my_module_status_id），测试里造一个自己的
  #   名字来验证「标签来自数据库」这条铁律；校验关掉。
  #   2026-10-04 QA 修：必须挂 my_module_status_flow —— 原生
  #   `MyModuleStatus#final_status?` 的实现是 `my_module_status_flow.final_status == self`，
  #   flow 为 nil 直接 NoMethodError（payload 的 final_status_ids 也跟着炸）。
  #   不挂 flow 造出来的「半个状态」是脏数据，不是生产形态。
  def make_status!(name:, color: '#3070ED')
    MyModuleStatus.find_by(name: name) || begin
      flow = MyModuleStatusFlow.order(:id).first ||
             MyModuleStatusFlow.create!(name: "WB-flow-#{SecureRandom.hex(2)}")
      status = MyModuleStatus.new(name: name, color: color, my_module_status_flow: flow)
      status.save(validate: false)
      status.persisted? ? status : (MyModuleStatus.order(:id).first)
    end
  end

  # 前提守卫：用例不该在「已经是 Owner」的前提下断言别的角色。
  #   ⚠ 2026-10-04 QA 修：minitest 用例之间**没有事务回滚**，上一个用例挂的
  #     Owner 赋值会留到下一个用例 → 直接 flunk 必挂。改成显式清干净再断言。
  # ⚠ 必须是 update_all（直接改 role），不能用 destroy_all：
  #   destroy Team 级 UserAssignment 会触发 UserAssignments::RemoveTeamUserAssignmentsService，
  #   里面拿不到 assigner/user 就 NoMethodError（已实测）。
  def strip_owner!(user)
    role = UserRole.where.not(name: 'Owner').order(:id).first
    return 0 if role.nil?

    ids = ::UserAssignment.joins(:user_role)
                          .where(user_id: user.id, user_roles: { name: 'Owner' })
                          .pluck(:id)
    ::UserAssignment.where(id: ids).delete_all # delete_all 不走回调，避开 RemoveTeamUserAssignmentsService
    warn "[strip_owner] user=#{user.id} owner_ids=#{ids.inspect}"
  end

  def final_status!
    MyModuleStatus.unscoped.select(&:final_status?).first || make_status!(name: 'WB-已完成')
  end

  # ⚠ 2026-10-04 QA 修：user_groups.last_modified_by_id 是 NOT NULL，
  #   原工厂只写 created_by → PG::NotNullViolation 7 处连坐。
  def make_user_group!(team:, name:)
    group = UserGroup.find_by(name: name, team_id: team.id)
    if group.nil?
      group = UserGroup.new(name: name, team_id: team.id,
                            created_by: team.created_by, last_modified_by: team.created_by)
      group.save(validate: false)
    end
    # ⚠ 兜底：不管上面哪条路径落的行，lmb 都必须是真值（该列 NOT NULL）。
    #   实测 find_or_create_by! 那条路径在用例里确实会插出 lmb=NULL 的行。
    group.update_column(:last_modified_by_id, team.created_by_id) if group && group.last_modified_by_id.nil?
    group
  rescue StandardError
    UserGroup.find_by(name: name, team_id: team.id)
  end

  # ⚠ 2026-10-04 QA 修：编号必须 `\ASQ-\d{4}-\d{4}\z`（ResourceApplication 校验），
  #   原来的 SQ-2026-<8位hex> 过不了 → RecordInvalid。用递增序号保证本轮唯一。
  def wb_app_no!
    @@wb_app_no_seq = (defined?(@@wb_app_no_seq) ? @@wb_app_no_seq : 9000) + 1
    format('SQ-2026-%04d', @@wb_app_no_seq)
  end

  def make_resource_application!(project:, requestor:, status: 'submitted')
    Scinote::ElnUi::ResourceApplication.create!(
      project: project,
      requestor: requestor,
      no: wb_app_no!,
      status: status,
      items: [{ kind: 'material', name: 'WB-基料', qty: 20, unit: 'kg', unit_price: 350.0 }]
    )
  end
end
