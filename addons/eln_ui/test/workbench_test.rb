# frozen_string_literal: true
#
# 个人行动工作台（Workbench）—— ADR-0048 契约测试
#
# 守 6 件事（都是「不许编 / 不许漂」的铁律落点）：
#   1. payload 恰好六块：meta / todos / approvals / projects / links / totals（Q12=A 平铺契约）；
#   2. meta.greeting / role / notice 全部来自真源（User 真名 / UserRole 按承载面分级 /
#      原生 Notification 未读数），不落演示文案；
#   3. todos 只收**未完成**任务（state=uncompleted ∧ 状态非 final）且全链路排除归档（Q2=B/Q14=A），
#      逾期置顶红标；我的申请待验货（ReceiptPendingBook 真源）并入待办区（Q3=A）；
#   4. approvals 三条「待我审」真源的判定一律问名单（ResourceApprovalPolicy /
#      TaskCloseWorkflow.reviewable_project_ids）—— 名单外的人看不到（fail-closed 反例）；
#   5. projects = ProjectListScope.participated（与「参与项目」KPI 同一真源），
#      「可读但非成员」的项目不进（Q4=A 口径反例）；
#   6. 所有 to / links 全部真源可达（recognize_path），前端不写死宿主路由。
#
# ⚠ 本文件所有 `def test_*` 必须留在文件末尾的 `private` **之前**，
#   否则 minitest 静默不执行（runs 数不动就是报警）。
# ⚠ minitest 用例之间**没有事务回滚**：所有断言必须锚定本场景自建的
#   user/team/project，别信「全库只有我这条」。

require_relative 'test_helper'

class WorkbenchTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  # ============================================================
  # 契约形状
  # ============================================================

  # 六块齐全（前端只读这六个 key；旧版 kpis/dist/groups/entries 已删，Q1=A）
  def test_payload_exposes_exactly_the_six_defined_blocks
    scene = build_scene!

    body = Scinote::ElnUi::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal %i[meta todos approvals projects links totals], body.keys
  end

  # ============================================================
  # meta：页头 / 角色徽章 / 通知栏
  # ============================================================

  # ① 问候语 = 时段 + 用户真名（不含原型的「张负责人」演出值）
  def test_meta_greeting_uses_real_user_full_name
    scene = build_scene!

    body = Scinote::ElnUi::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    greeting = body[:meta][:greeting]
    refute_nil greeting, '问候语必须有值'
    assert_includes greeting, scene[:creator].full_name, '问候语必须带用户真名'
    assert_match(/^(凌晨|上午|下午|晚上)好，/, greeting, '问候语必须是「时段好，真名」形状')
  end

  # ② 普通组员：非 Team 级 Owner、也非任何可读 project 的负责人 → 「普通组员」
  def test_role_is_plain_member_for_plain_user
    scene = build_scene!
    strip_owner!(scene[:creator])

    body = Scinote::ElnUi::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal '普通组员', body[:meta][:role]
  end

  # ③ 单位管理员：**Team 级**（单位级）宿主 UserRole = Owner（只认 name，不认 id）
  def test_role_is_admin_when_owner_assignment_exists
    scene = build_scene!
    make_owner_assignment!(user: scene[:creator], team: scene[:team])

    body = Scinote::ElnUi::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal '单位管理员 · Owner', body[:meta][:role]
  end

  # ③-b 🔴 护栏：Project 级 Owner **不是**单位管理员（多态表必须限承载面）
  def test_role_is_not_admin_for_project_level_owner_only
    scene = build_scene!(visibility: :visible)
    project = make_project!(team: scene[:team], creator: scene[:creator], visibility: :visible)
    strip_owner!(scene[:creator])
    ensure_team_member!(scene[:creator], scene[:team], role: 'User')
    make_owner_assignment!(user: scene[:creator], team: scene[:team], assignable: project)

    assert_equal false, team_owner_assignment?(scene[:creator], scene[:team]),
                 '前提守卫失败：Team 级仍有 Owner 赋值，两种成因混在一起'
    assert_equal true, project_owner_assignment?(scene[:creator], project),
                 '前提守卫失败：Project 级 Owner 没挂上，用例退化成空断言'

    body = Scinote::ElnUi::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    refute_equal '单位管理员 · Owner', body[:meta][:role],
                 'Project 级 Owner 被误判成单位管理员 —— 角色判定没限定 assignable_type'
    assert_equal '项目负责人', body[:meta][:role]
  end

  # ④ 项目负责人：任一**可读** project 的 supervised_by 是自己（OPEN-1 双轨）
  def test_role_is_project_lead_when_supervising_readable_project
    scene = build_scene!(visibility: :visible)
    project = make_project!(team: scene[:team], creator: scene[:creator], visibility: :visible)
    project.update_column(:supervised_by_id, scene[:creator].id)
    strip_owner!(scene[:creator])
    ensure_team_member!(scene[:creator], scene[:team], role: 'User')
    allow_project_read!(project, scene[:creator], role: 'User')

    still_owner = ::UserAssignment.joins(:user_role)
                                  .where(user_id: scene[:creator].id, user_roles: { name: 'Owner' })
                                  .exists?
    assert_equal false, still_owner, '前提守卫失败：Owner 赋值未清干净'
    assert project.readable_by_user?(scene[:creator]),
           "前提守卫失败：项目已不可读（project_lead? 会落空）visibility=#{project.visibility.inspect}"

    body = Scinote::ElnUi::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal '项目负责人', body[:meta][:role]
  end

  # ⑤ 通知栏：0 条未读 → 「暂无未读通知」（状态描述，不是演示文案）
  def test_notice_reports_empty_state_when_no_unread
    scene = build_scene!
    ::Notification.where(recipient_type: 'User', recipient_id: scene[:creator].id, read_at: nil).delete_all

    body = Scinote::ElnUi::WorkbenchPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal '暂无未读通知', body[:meta][:notice]
  end

  # ⑥ 通知栏：有未读 → 「N 条未读通知」（只有条数，不编触发源细目 —— OPEN-WORKBENCH-2）
  def test_notice_reports_real_unread_count
    scene = build_scene!
    user = scene[:creator]
    ::Notification.where(recipient_type: 'User', recipient_id: user.id, read_at: nil).delete_all
    ::Notification.create!(type: 'GeneralNotification', recipient: user, params: {})
    expected = ::Notification.where(recipient_type: 'User', recipient_id: user.id, read_at: nil).count

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    assert_equal "#{expected} 条未读通知", body[:meta][:notice]
    assert_operator expected, :>=, 1, '用例必须真的造出 1 条未读，否则这条断言是空断言'
  end

  # ============================================================
  # todos：待办事项（我的未完成任务 + 我的申请待验货）
  # ============================================================

  # ① 被指派给我的未完成任务进待办；to 指向任务详情页（真源可达）
  def test_todo_for_my_assigned_uncompleted_module
    scene = build_scene!
    user = scene[:creator]
    project = member_project!(scene)
    exp = make_experiment!(project: project, creator: user)
    mod = make_task!(experiment: exp, creator: user)
    ua = ua_for(mod, user)
    refute_nil ua, '任务必须有 UserAssignment 才能算「我的任务」'

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    todo = body[:todos].find { |t| t[:title] == mod.name }
    refute_nil todo, '被指派的未完成任务必须出现在待办里'
    assert_equal 'task', todo[:kind]
    assert_equal '任务', todo[:type]
    assert_equal '—', todo[:due], 'due_date 无值 → 显式留白，不编日期'
    assert_equal false, todo[:overdue]
    refute_nil todo[:status]
    assert_includes todo[:to], "/my_modules/#{mod.id}/eln_task_detail", '待办必须带任务详情跳转'
    assert_routable(todo[:to])
  end

  # ② 已完成 / 终态 / 已归档任务**不进**待办（Q2=B 只收未完成）
  def test_completed_and_final_and_archived_modules_are_excluded
    scene = build_scene!
    user = scene[:creator]
    project = member_project!(scene)
    exp = make_experiment!(project: project, creator: user)

    completed = make_task!(experiment: exp, creator: user, name: 'WB-已完成任务')
    completed.update_column(:state, 'completed')

    final = make_task!(experiment: exp, creator: user, name: 'WB-终态任务')
    final.update_column(:my_module_status_id, final_status!.id)

    archived_mod = make_task!(experiment: exp, creator: user, name: 'WB-已归档任务')
    archived_mod.update_column(:archived, true)

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    titles = body[:todos].map { |t| t[:title] }
    refute_includes titles, 'WB-已完成任务', 'state=completed 不是「需要处理的事」'
    refute_includes titles, 'WB-终态任务', '终态任务不是「需要处理的事」'
    refute_includes titles, 'WB-已归档任务', '已归档任务不进待办（Q14=A）'
  end

  # ③ 归档项目 / 归档实验下的未完成任务不进待办（Q14=A 全链路排除归档）
  def test_modules_under_archived_project_or_experiment_are_excluded
    scene = build_scene!
    user = scene[:creator]

    archived_project = member_project!(scene, name: 'WB-归档项目')
    archived_project.update_column(:archived, true)
    exp_a = make_experiment!(project: archived_project, creator: user)
    mod_a = make_task!(experiment: exp_a, creator: user, name: 'WB-归档项目任务')

    live_project = member_project!(scene, name: 'WB-活动项目')
    exp_b = make_experiment!(project: live_project, creator: user)
    exp_b.update_column(:archived, true)
    mod_b = make_task!(experiment: exp_b, creator: user, name: 'WB-归档实验任务')

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    titles = body[:todos].map { |t| t[:title] }
    refute_includes titles, 'WB-归档项目任务', '归档项目下的任务不进待办'
    refute_includes titles, 'WB-归档实验任务', '归档实验下的任务不进待办'
  end

  # ④ 逾期置顶红标；今天到期不算逾期（Q2=B 边界口径）
  def test_overdue_todo_is_pinned_first_with_danger_tone
    scene = build_scene!
    user = scene[:creator]
    project = member_project!(scene)
    exp = make_experiment!(project: project, creator: user)

    overdue_mod = make_task!(experiment: exp, creator: user, name: 'WB-逾期任务')
    overdue_mod.update_column(:due_date, Time.zone.today - 1)

    today_mod = make_task!(experiment: exp, creator: user, name: 'WB-今天到期任务')
    today_mod.update_column(:due_date, Time.zone.today)

    future_mod = make_task!(experiment: exp, creator: user, name: 'WB-未来任务')
    future_mod.update_column(:due_date, Time.zone.today + 5)

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    titles = body[:todos].map { |t| t[:title] }
    assert_equal 'WB-逾期任务', titles.first, '逾期任务必须置顶'
    overdue = body[:todos].find { |t| t[:title] == 'WB-逾期任务' }
    assert_equal true, overdue[:overdue], 'due_date 早于今天 → overdue'
    assert_equal 'danger', overdue[:tone], '逾期 → danger 色调（前端渲染红标）'
    assert_includes overdue[:due], (Time.zone.today - 1).strftime('%m-%d')

    today = body[:todos].find { |t| t[:title] == 'WB-今天到期任务' }
    assert_equal false, today[:overdue], '今天到期**不算**逾期（边界口径）'
    assert_equal 'warn', today[:tone]

    assert_operator titles.index('WB-未来任务'), :>, titles.index('WB-今天到期任务'),
                    '未逾期区按截止日近 → 远'
  end

  # ⑤ 我的申请待验货进待办（申请人侧欠账，ReceiptPendingBook 单一真源）
  def test_my_unverified_material_application_appears_in_todos
    scene = build_scene!
    user = scene[:creator]
    project = member_project!(scene)
    mine = make_resource_application!(project: project, requestor: user, status: 'project_approved')
    # 服务类**永远不经历货**（SCN-RES-APPROVE-4）→ 不得进待验货
    service = make_resource_application!(project: project, requestor: user, status: 'project_approved',
                                         kind: 'service')

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    todo = body[:todos].find { |t| t[:kind] == 'receipt_pending' && t[:title].include?(mine.no) }
    refute_nil todo, '我的材料申请已终审未验货 → 进待办（Q3=A）'
    assert_equal '资源申请 · 待验货', todo[:type]
    assert_equal '待验货', todo[:status]
    assert_includes todo[:to], "/eln_res_apply/#{mine.no}"
    assert_routable(todo[:to])
    refute body[:todos].any? { |t| t[:title].include?(service.no) },
           '服务类申请不进待验货（服务不经历货）'
  end

  # ============================================================
  # approvals：审批事项（待我审，三条真源）
  # ============================================================

  # ① 资源申请：被配为审批人 → 看得见（submitted=待初审 / group_approved=待终审）
  def test_resource_application_visible_to_configured_approver
    scene = build_scene!
    team = scene[:team]
    approver = join_team!(make_user!(name: 'wb-approver'), team)
    requestor = join_team!(make_user!(name: 'wb-requestor'), team)
    project = make_project!(team: team, creator: requestor, visibility: :visible)
    configure_approver!(user: approver, project: project, stages: %w[group project])
    allow_project_read!(project, approver)
    submitted = make_resource_application!(project: project, requestor: requestor, status: 'submitted')
    final_review = make_resource_application!(project: project, requestor: requestor, status: 'group_approved')

    body = Scinote::ElnUi::WorkbenchPayload.call(user: approver, team: team)

    first = body[:approvals].find { |a| a[:title].include?(submitted.no) }
    refute_nil first, '被配为初审人的用户必须看见 submitted 单'
    assert_equal 'resource_application', first[:kind]
    assert_equal '待初审', first[:status]
    second = body[:approvals].find { |a| a[:title].include?(final_review.no) }
    refute_nil second, '被配为终审人的用户必须看见 group_approved 单'
    assert_equal '待终审', second[:status]
  end

  # ② 🔴 fail-closed 反例：不在名单里 → 看不见（哪怕同队、哪怕不是本人提交）
  def test_resource_application_hidden_from_non_approver
    scene = build_scene!
    team = scene[:team]
    outsider = join_team!(make_user!(name: 'wb-outsider'), team)
    requestor = join_team!(make_user!(name: 'wb-requestor2'), team)
    project = make_project!(team: team, creator: requestor, visibility: :visible)
    clear_approvers!(project)
    make_resource_application!(project: project, requestor: requestor, status: 'submitted')

    body = Scinote::ElnUi::WorkbenchPayload.call(user: outsider, team: team)

    refute body[:approvals].any? { |a| a[:kind] == 'resource_application' },
           '名单外用户不得看见待审申请（fail-closed，ADR-0029）'
  end

  # ③ 任务关闭审核：项目 Owner（Project 级 Owner UA）看得见 pending 单；
  #    非 Owner 看不见（与 TaskCloseWorkflow.reviewer? 同口径）
  def test_task_close_request_visible_to_project_owner_only
    scene = build_scene!
    team = scene[:team]
    owner = join_team!(make_user!(name: 'wb-close-owner'), team)
    mate = join_team!(make_user!(name: 'wb-close-mate'), team)
    project = make_project!(team: team, creator: owner, visibility: :visible)
    make_project_owner!(project, user: owner, team: team)
    exp = make_experiment!(project: project, creator: owner)
    mod = make_task!(experiment: exp, creator: owner)
    make_task_close_request!(my_module: mod, submitted_by: mate)

    owner_body = Scinote::ElnUi::WorkbenchPayload.call(user: owner, team: team)
    row = owner_body[:approvals].find { |a| a[:kind] == 'task_close' }
    refute_nil row, '项目 Owner 必须看见任务关闭待审（Q3=A）'
    assert_equal '任务关闭', row[:type]
    assert_equal '待审核', row[:status]
    assert_includes row[:to], "/my_modules/#{mod.id}/eln_task_detail"
    assert_routable(row[:to])

    mate_body = Scinote::ElnUi::WorkbenchPayload.call(user: mate, team: team)
    refute mate_body[:approvals].any? { |a| a[:kind] == 'task_close' },
           '非项目 Owner 不得看见任务关闭待审（与 reviewer? 闸门同口径）'
  end

  # ④ 到货验收：receipt 阶段名单内的人看得见 project_approved 材料单
  def test_receipt_verification_visible_to_receipt_stage_approver
    scene = build_scene!
    team = scene[:team]
    verifier = join_team!(make_user!(name: 'wb-verifier'), team)
    requestor = join_team!(make_user!(name: 'wb-req3'), team)
    project = make_project!(team: team, creator: requestor, visibility: :visible)
    configure_approver!(user: verifier, project: project, stages: %w[receipt])
    allow_project_read!(project, verifier)
    app = make_resource_application!(project: project, requestor: requestor, status: 'project_approved')

    body = Scinote::ElnUi::WorkbenchPayload.call(user: verifier, team: team)

    row = body[:approvals].find { |a| a[:kind] == 'receipt' && a[:title].include?(app.no) }
    refute_nil row, 'receipt 名单内的人必须看见待验货材料单（Q3=A）'
    assert_equal '到货验收', row[:type]
    assert_equal '待验货', row[:status]
    assert_routable(row[:to])
  end

  # ⑤ 审批事项按来源分小段（前端按 kind 分组；段名取首条 type，不硬编）
  def test_approvals_carry_kind_and_type_for_frontend_grouping
    scene = build_scene!
    team = scene[:team]
    approver = join_team!(make_user!(name: 'wb-approver2'), team)
    requestor = join_team!(make_user!(name: 'wb-requestor4'), team)
    project = make_project!(team: team, creator: requestor, visibility: :visible)
    configure_approver!(user: approver, project: project, stages: %w[group project receipt])
    allow_project_read!(project, approver)
    make_resource_application!(project: project, requestor: requestor, status: 'submitted')

    body = Scinote::ElnUi::WorkbenchPayload.call(user: approver, team: team)

    body[:approvals].each do |a|
      refute_nil a[:kind], '每条审批必须带稳定 kind（前端分组用）'
      refute_nil a[:type], '每条审批必须带展示标签 type（业务命名不下发到组件）'
      refute_nil a[:status]
      refute_nil a[:tone]
    end
  end

  # ============================================================
  # projects：进行中的项目（参与 ∩ 活动，Q4=A）
  # ============================================================

  # ① 我参与的活动项目进列表：三态标签 + 我的角色 + 任务摘要 + 详情跳转
  def test_participated_active_project_appears_with_status_role_and_summary
    scene = build_scene!
    user = scene[:creator]
    project = member_project!(scene, name: 'WB-在研项目')
    project.update_column(:started_at, Time.zone.today)
    exp = make_experiment!(project: project, creator: user)
    make_task!(experiment: exp, creator: user)
    make_task!(experiment: exp, creator: user)
    done_mod = make_task!(experiment: exp, creator: user)
    done_mod.update_column(:state, 'completed')

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    row = body[:projects].find { |p| p[:name] == 'WB-在研项目' }
    refute_nil row, '我参与的活动项目必须出现（Q4=A）'
    assert_equal 'active', row[:status]
    assert_equal '进行中', row[:statusLabel]
    assert_equal '负责', row[:role], '创建者 = Project 级 Owner UA → 负责（双轨）'
    assert_equal '2 个任务待办', row[:taskSummary], '只数未完成任务（完成的那条不算）'
    assert_includes row[:to], "/projects/#{project.id}/eln_project_detail"
    assert_routable(row[:to])
  end

  # ② 归档项目不进；「可读但非成员」的项目不进（Q4=A 口径反例）
  def test_archived_and_non_member_projects_are_excluded
    scene = build_scene!
    user = scene[:creator]
    team = scene[:team]

    archived = member_project!(scene, name: 'WB-已结题项目')
    archived.update_column(:archived, true)

    stranger = join_team!(make_user!(name: 'wb-stranger2'), team)
    foreign = make_project!(team: team, creator: stranger, visibility: :visible)
    ::TeamAssignment.create!(assignable: foreign, team: team,
                             user_role: ::UserRole.find_predefined_normal_user_role,
                             assigned: :manually)
    assert foreign.readable_by_user?(user), '前提守卫：foreign 必须可读'
    assert_nil ua_for(foreign, user), '前提守卫：foreign 必须非成员'

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: team)

    names = body[:projects].map { |p| p[:name] }
    refute_includes names, 'WB-已结题项目', '归档项目不进工作台'
    refute_includes names, foreign.name, '可读但非成员的项目不进（参与口径，Q4=A）'
  end

  # ============================================================
  # links / totals
  # ============================================================

  # ① 「查看全部」只接已有承载面：项目区带成员筛选 + view_mode=active；
  #    资源申请段指向资源中心申请单 tab；两者都真源可达
  def test_links_target_only_existing_surfaces_and_are_routable
    scene = build_scene!
    user = scene[:creator]

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    assert_includes body[:links][:projectsAll], "filters%5Bmembers%5D%5B%5D=#{user.id}",
                    '项目区「查看全部」必须带「成员=我」筛选'
    assert_includes body[:links][:projectsAll], 'view_mode=active'
    assert_includes body[:links][:resourceApplicationsAll], 'tab=apply',
                    '资源申请段指向资源中心申请单页签'
    assert_routable(body[:links][:projectsAll])
    assert_routable(body[:links][:resourceApplicationsAll])
  end

  # ② totals 是真实总数（与列表同口径）：待办 = 未完成任务 + 待验货申请
  def test_totals_report_real_counts
    scene = build_scene!
    user = scene[:creator]
    project = member_project!(scene)
    exp = make_experiment!(project: project, creator: user)
    make_task!(experiment: exp, creator: user)
    make_task!(experiment: exp, creator: user)
    done_mod = make_task!(experiment: exp, creator: user)
    done_mod.update_column(:state, 'completed')
    make_resource_application!(project: project, requestor: user, status: 'project_approved')

    body = Scinote::ElnUi::WorkbenchPayload.call(user: user, team: scene[:team])

    assert_equal 3, body[:totals][:todos], '待办总数 = 2 条未完成任务 + 1 条待验货申请'
    assert_equal 0, body[:totals][:approvals], '本场景没有待我审的单（我没被配进任何名单）'
    assert_operator body[:totals][:projects], :>=, 1
  end

  # ============================================================
  # 完成率基准：final_status_ids 的批量取法必须等价于逐条 final_status?
  # ============================================================

  # ⚠ 这条用例锁的是「口径不变」—— 有人再把它下推成「id 不在任何 previous_status_id 里」
  #   那种 SQL 会立刻红：同一 flow 里允许挂多条互不相连的状态，
  #   「没有后继」的状态不止一个，而 flow.final_status 只认其中一条 → 完成率被算高。
  def test_final_status_ids_matches_native_predicate
    make_status!(name: 'WB-终态基准') if ::MyModuleStatus.unscoped.count.zero?

    ruby_ids = ::MyModuleStatus.unscoped.select(&:final_status?).map(&:id).uniq.sort
    batched_ids = ::Scinote::ElnUi::WorkbenchPayload.new(user: nil, team: nil)
                                                        .send(:final_status_ids).sort

    refute_empty ruby_ids, '至少得有一个真终态，否则这条断言是空断言'
    assert_equal ruby_ids, batched_ids, 'final_status_ids 的批量取法与逐条 final_status? 不一致'
  end

  # ============================================================
  # 私有工厂（只在这里被上面的用例调用）
  # ============================================================

  private

  # 反向护栏：跳转目标必须真能 match 到宿主路由表（去掉 query 再识别）。
  #   只断言「字符串以 / 开头」抓不住「形状像但路由里没有」这类错 ——
  #   隔壁 notifications_payload 就是手写了一个少一段的 URL，且被写进断言，
  #   套件长期全绿、真机 404。所以这里过一遍真实路由识别。
  def assert_routable(to)
    path = to.to_s.split('?').first
    Rails.application.routes.recognize_path(path, method: :get)
  rescue ActionController::RoutingError => e
    flunk "跳转目标匹配不到任何宿主路由：#{to}（#{e.message}）"
  end

  # 建一个「creator 可见 + 是成员」的项目。⚠ AcTest 的 make_project! 没有 name 参，
  # 名字用 update_column 补（可见性不影响 readable_by_user —— 那是纯权限判定，
  # 但保持 visible 与生产主形态一致）。
  def member_project!(scene, name: nil)
    project = make_project!(team: scene[:team], creator: scene[:creator], visibility: :visible)
    project.update_column(:name, name) if name
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
  # 删完 user.permission_team 变 nil，而 readable_by_user? 是 team 作用域，
  # 所以 strip 之后要把「人是队成员」接回来，用**非 Owner**角色。
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

  # 造一条 Owner 赋值。assignable 默认 **team**（「单位管理员」的正确承载面）；
  # 传 project 会造出「项目级 Owner」，那是**项目负责人**不是单位管理员。
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
  #   名字来验证「标签来自数据库」这条铁律；必须挂 my_module_status_flow ——
  #   原生 `MyModuleStatus#final_status?` 的实现是 `my_module_status_flow.final_status == self`，
  #   flow 为 nil 直接 NoMethodError（payload 的 final_status_ids 也跟着炸）。
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
  #   ⚠ minitest 用例之间**没有事务回滚**，上一个用例挂的 Owner 赋值会留到
  #     下一个用例 → 直接 flunk 必挂。改成显式清干净再断言。
  # ⚠ 必须是 delete_all（直接删行），不能用 destroy_all：
  #   destroy Team 级 UserAssignment 会触发 UserAssignments::RemoveTeamUserAssignmentsService，
  #   里面拿不到 assigner/user 就 NoMethodError（已实测）。
  def strip_owner!(user)
    role = UserRole.where.not(name: 'Owner').order(:id).first
    return 0 if role.nil?

    ids = ::UserAssignment.joins(:user_role)
                          .where(user_id: user.id, user_roles: { name: 'Owner' })
                          .pluck(:id)
    ::UserAssignment.where(id: ids).delete_all
    warn "[strip_owner] user=#{user.id} owner_ids=#{ids.inspect}"
  end

  def final_status!
    MyModuleStatus.unscoped.select(&:final_status?).first || make_status!(name: 'WB-已完成')
  end

  # ⚠ 编号必须 `\ASQ-\d{4}-\d{4}\z`（ResourceApplication 校验）。
  #   kind: 'material'（默认，经历货）/ 'service'（不经历货）。
  def wb_app_no!
    @@wb_app_no_seq = (defined?(@@wb_app_no_seq) ? @@wb_app_no_seq : 9000) + 1
    format('SQ-2026-%04d', @@wb_app_no_seq)
  end

  def make_resource_application!(project:, requestor:, status: 'submitted', kind: 'material')
    Scinote::ElnUi::ResourceApplication.create!(
      project: project,
      requestor: requestor,
      no: wb_app_no!,
      status: status,
      items: [{ kind: kind, name: "WB-#{kind}", qty: 20, unit: 'kg', unit_price: 350.0 }]
    )
  end
end
