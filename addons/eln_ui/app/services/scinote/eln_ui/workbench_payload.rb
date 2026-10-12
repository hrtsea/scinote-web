# frozen_string_literal: true

# 个人行动工作台（Workbench）—— 「每天从这里开始：只显示需要处理的事」（ADR-0048）
#
# 形状（grilling Q1~Q15 定型，2026-10-12）：
#   meta:    { greeting, role, updatedAt, notice }
#   todos:   [{ kind:'task'|'receipt_pending', type, title, due, overdue, status, tone, to }]
#   approvals:[{ kind:'resource_application'|'task_close'|'receipt', type, title, due, status, tone, to }]
#   projects:[{ name, status, statusLabel, role, taskSummary, to }]
#   links:   { projectsAll, resourceApplicationsAll }   # 无承载面 ⇒ nil（显式留白）
#   totals:  { todos, approvals, projects }             # 真实总数（超 20 时「共 M 条」用）
#
# 与旧版（ADR-0045 合并时的六块仪表盘）的本质区别：旧版回答「有多少」（KPI/分布/小组），
# 本版回答「我现在该做什么」。统计块已全删（Q1=A）——工作台不复述别处已有的数字。
#
# 六条口径（全部来自 grilling 裁决，勿改）：
#   1. 「你能看到」= readable_by_user ∩ current_team（Q5=A，team 闸门不变）。
#   2. 待办只收**未完成**任务（state=uncompleted ∧ 状态非 final），逾期置顶红标（Q2=B）。
#   3. 审批收四条真源（Q3=A）：资源申请初审/终审、任务关闭、到货验收（「待我审」）
#      + 我的申请待验货（申请人侧，入待办区）。判定一律问名单真源，工作台不自己推断。
#   4. 「正在进行的项目」= ProjectListScope.participated（Q4=A）——与「参与项目」KPI
#      同一真源，两侧数字必须逐位相等。
#   5. 全链路排除归档（Q14=A）：项目 ∩ 实验 ∩ 任务 均未归档。
#   6. 每条都必须点进去能动（Q11=A/Q15=A）：工作台是「发现器」，动作在详情页做。
#      URL 全部由本服务用宿主/引擎真实 path helper 下发（前端不写死宿主路由）。
#
# 权限模型（access_control D8 同源同层，不新建权限位）：
#   任务/项目面 = 原生 Canaid（Project.readable_by_user）；审批面 = 名单真源
#   （ResourceApprovalPolicy / TaskCloseWorkflow.reviewable_project_ids）。
module Scinote
  module ElnUi
    class WorkbenchPayload
      # 宿主 UserRole 真名（Owner / User / Technician / Viewer），不认 id。
      OWNER_ROLE_NAME = 'Owner'
      ROLE_ADMIN = '单位管理员'
      ROLE_LEAD = '项目负责人'
      ROLE_MEMBER = '普通组员'
      ROLE_ADMIN_WITH_OWNER = "#{ROLE_ADMIN} · #{OWNER_ROLE_NAME}"

      # 🔴 UserAssignment 是**多态**表，角色判定必须限定承载面。
      #   不加这两个常量就会出现「项目上的 Owner 被算成单位管理员」——
      #   见 team_admin? 上方的事故记录。以后新增角色判定，先问「承载面是哪一级」。
      TEAM_ASSIGNABLE_TYPE = 'Team'
      PROJECT_ASSIGNABLE_TYPE = 'Project'

      # 三区上限（Q10=B：与宿主 AG Grid 默认页大小一致）。
      TODO_LIMIT = 20
      APPROVAL_LIMIT = 20
      PROJECT_LIMIT = 20

      # 无真源时的显式留白（不是演示文案）
      DASH = '—'

      # 项目三态标签（status 值复用 project_list_payload#status_of 的推导：
      #   done_at 有值=done / started_at 空=notstarted / 否则 active）
      PROJECT_STATUS_LABELS = { 'notstarted' => '未开始', 'active' => '进行中', 'done' => '已完成' }.freeze

      class << self
        def call(user:, team:)
          new(user: user, team: team).call
        end
      end

      def initialize(user:, team:)
        @user = user
        @team = team
      end

      def call
        {
          meta: meta_block,
          todos: todos_block,
          approvals: approvals_block,
          projects: projects_block,
          links: links_block,
          totals: totals_block
        }
      end

      private

      # 宿主真实 path helper 的唯一入口（本服务所有链接都走它）。
      #   ⚠ 必须真的存在：写错 helper 名 = 加载期 NoMethodError，
      #   这是好事（当场炸），别再包一层 rescue 把它变成静默兜底。
      def host_routes
        @host_routes ||= ::Rails.application.routes.url_helpers
      end

      # ------------------------------------------------------------
      # 共用 scope（一次 memo，全类复用）
      # ------------------------------------------------------------
      # 当前 team 下「我能读」的 project（Canaid 同源同层）
      def readable_projects
        @readable_projects ||= ::Project.readable_by_user(@user).where(team_id: @team.id)
      end

      # Q14=A：三区全链路排除归档 —— 项目级先筛 active
      def active_readable_projects
        @active_readable_projects ||= readable_projects.active
      end

      def active_readable_project_ids
        @active_readable_project_ids ||= active_readable_projects.pluck(:id)
      end

      # 「我负责的项目」ids（双轨，与 ProjectListScope.responsible_condition 同语义）。
      # ⚠ 用 Arel 条件而不是逐项目问 ORM：20 个项目 = 20 次查询正是本仓禁止的形态。
      def responsible_project_ids
        @responsible_project_ids ||= ::Project.where(team_id: @team.id)
                                              .where(::Scinote::ElnUi::ProjectListScope.responsible_condition(@user))
                                              .pluck(:id)
      end

      # ------------------------------------------------------------
      # 1. meta（页头：问候 + 角色徽标 + 更新时间 + 未读通知）
      #    statusMachine 随分布图一并删除（Q1=A）。
      # ------------------------------------------------------------
      def meta_block
        {
          greeting: greeting_value,
          role: role_value,
          updatedAt: "数据更新于 #{Time.current.strftime('%H:%M')}",
          notice: notice_value
        }
      end

      def greeting_value
        "#{period_word}好，#{@user.full_name}"
      end

      def period_word
        case Time.current.hour
        when 0...6 then '凌晨'
        when 6...12 then '上午'
        when 12...18 then '下午'
        else '晚上'
        end
      end

      def role_value
        return ROLE_ADMIN_WITH_OWNER if team_admin?
        return ROLE_LEAD if project_lead?

        ROLE_MEMBER
      end

      # 「单位管理员」= 当前**单位（Team）**上的宿主角色是 Owner。
      #
      # 🔴 2026-10-05 修（原实现把三种人混算成一种）：
      #   原写法不限 assignable_type，于是「在某个 Project / Experiment / MyModule 上
      #   挂着 Owner」也被算作单位管理员。生产实测（4 个用户的库）：3 个被贴上
      #   「单位管理员 · Owner」，而全库 Team 级 Owner 只有 1 条。
      def team_admin?
        return false if @user.nil? || @team.nil?

        ::UserAssignment.where(user_id: @user.id,
                               assignable_type: TEAM_ASSIGNABLE_TYPE,
                               assignable_id: @team.id)
                        .joins(:user_role)
                        .where(user_roles: { name: OWNER_ROLE_NAME })
                        .exists?
      end

      # 「项目负责人」双轨（OPEN-1）：supervised_by 或 Project 级 Owner，命中任一即算。
      #   生产实据 —— 两条轨道各有一半人，只认一条必然把另一半降级：
      #     dy@qq.com      : Project 级 Owner 283 个 / supervised_by 0 个
      #     hrtsea@qq.com  : supervised_by 203 个 / Project 级 Owner 4 个
      def project_lead?
        return false if @user.nil?

        readable_projects.where(supervised_by_id: @user.id).exists? || project_owner?
      end

      def project_owner?
        ::UserAssignment.where(user_id: @user.id, assignable_type: PROJECT_ASSIGNABLE_TYPE)
                        .where(assignable_id: readable_projects.select(:id))
                        .joins(:user_role)
                        .where(user_roles: { name: OWNER_ROLE_NAME })
                        .exists?
      end

      # ⚠ 原生 Notification 只有 GeneralNotification / ActivityNotification 两态，
      #   没有细粒度触发源分类（OPEN-WORKBENCH-2）→ 只报条数，不编细目。
      def notice_value
        count = unread_notification_count
        count.to_i.zero? ? '暂无未读通知' : "#{count} 条未读通知"
      end

      # 未读数走 **eln_ui 的单一真源**（NotificationsPayload.unread_count_for）——
      # 宿主顶栏徽标（navigations_controller.rb:103）与通知中心列表用的是同一个
      # `notifications.in_app.where(read_at: nil)` 口径。三处必须是同一个数。
      def unread_notification_count
        ::Scinote::ElnUi::NotificationsPayload.unread_count_for(@user)
      end

      # ------------------------------------------------------------
      # 2. todos（待办事项：我的未完成任务 + 我的申请待验货）
      #    Q2=B：未完成（state=uncompleted ∧ 状态非 final），逾期置顶红标
      #    （due_date 早于今天；今天到期不算逾期但排最前）。
      #    Q14=A：项目 ∩ 实验 ∩ 任务 均未归档。
      # ------------------------------------------------------------
      def todos_block
        entries = task_todo_entries + receipt_todo_entries
        sort_todos(entries).first(TODO_LIMIT).map { |entry| entry[:item] }
      end

      # 排序键（一次算清，避免在 map 里反复问 ORM）：
      #   ① 逾期（due < 今天）置顶；
      #   ② 其余按 due 升序，无 due 的排最后；
      #   ③ 同 due 按创建时间倒序；再同按 id 倒序（确定性，防 sort 不稳定）。
      def sort_todos(entries)
        far_future = Date.new(9999, 12, 31)
        entries.sort_by do |e|
          due = e[:due_date]
          [due && due < Time.zone.today ? 0 : 1,
           due || far_future,
           -e[:created_at].to_i,
           -e[:id]]
        end
      end

      def task_todo_entries
        my_open_tasks.order(TASK_TODO_ORDER).limit(TODO_LIMIT).map do |mod|
          { due_date: mod.due_date, created_at: mod.created_at, id: mod.id, item: task_todo(mod) }
        end
      end

      # 我的申请待验货（申请人侧欠账，Q3=A 并入待办区）。
      # ⚠ 复用 ReceiptPendingBook.for_applicant（单一真源：project_approved ∧ 材料类 ∧
      #   未达验货阈值），只在 Ruby 侧补筛 team ∧ 未归档 —— 该类按申请人计数、
      #   不过 team，而工作台是 team 视角（Q5=A）。申请人侧单子量级小，Ruby 筛不开SQL。
      def receipt_todo_entries
        receipt_todo_apps.sort_by { |app| [app.created_at, app.id] }
                         .reverse
                         .first(TODO_LIMIT)
                         .map { |app| receipt_todo_entry(app) }
      end

      def receipt_todo_entry(app)
        { due_date: nil, created_at: app.created_at, id: app.id, item: receipt_todo(app) }
      end

      def task_todo(mod)
        status = statuses_by_id[mod.my_module_status_id]
        {
          kind: 'task',
          type: '任务',
          title: mod.name.to_s,
          due: due_label(mod),
          overdue: overdue?(mod),
          status: status&.name.to_s.presence || DASH,
          tone: overdue?(mod) ? 'danger' : 'warn',
          to: task_url(mod)
        }
      end

      def receipt_todo(app)
        {
          kind: 'receipt_pending',
          type: '资源申请 · 待验货',
          title: approval_title(app),
          due: DASH,
          overdue: false,
          status: '待验货',
          tone: 'warn',
          to: host_routes.eln_res_apply_detail_path(app.no).to_s
        }
      end

      # 我的未完成任务（Q2=B + Q14=A）。scope 与总数查询共用（limit 只加在列表侧）。
      def my_open_tasks
        scope = ::MyModule.where(experiment_id: unarchived_experiment_ids.select(:id))
                          .where(archived: false, state: 'uncompleted')
        # 状态非 final。⚠ final_status_ids 可能为空（没配 flow）——
        # 空数组进 where.not 会变成 `IS NOT NULL`，把无状态任务误杀，故必须守卫。
        scope = scope.where.not(my_module_status_id: final_status_ids) if final_status_ids.any?
        scope.joins(:user_assignments)
             .where(user_assignments: { user_id: @user.id })
             .distinct
      end

      TASK_TODO_ORDER = Arel.sql('my_modules.due_date ASC NULLS LAST, my_modules.created_at DESC').freeze

      def unarchived_experiment_ids
        ::Experiment.where(project_id: active_readable_project_ids, archived: false)
      end

      def overdue?(mod)
        mod.due_date.present? && mod.due_date < Time.zone.today
      end

      # due_date 是真列（my_modules.due_date），有值才写，没值就 '—'
      def due_label(mod)
        return DASH if mod.due_date.blank?

        mod.due_date.strftime('%m-%d')
      end

      def task_url(mod)
        return nil if mod.experiment_id.blank?

        host_routes.eln_task_detail_path(mod.experiment_id, mod).to_s
      end

      # ------------------------------------------------------------
      # 3. approvals（审批事项：待我审，Q3=A 四条真源之三）
      #    段序固定（资源申请 → 任务关闭 → 到货验收），段内提交时间倒序（Q8=A）。
      #    ⚠ 全区上限 APPROVAL_LIMIT：资源申请独占 20 条时后两段会让位
      #      （极端场景；真实总数见 totals，资源申请段有「查看全部」承载）。
      # ------------------------------------------------------------
      def approvals_block
        (resource_approval_apps.first(APPROVAL_LIMIT).map { |app| resource_approval(app) } +
         task_close_requests.first(APPROVAL_LIMIT).map { |req| task_close_approval(req) } +
         receipt_apps.first(APPROVAL_LIMIT).map { |app| receipt_approval(app) }).first(APPROVAL_LIMIT)
      end

      # ① 资源申请（submitted 待初审 / group_approved 待终审）。
      #   口径 = ResourceApprovalPolicy.approvable_project_ids（负责人 ∪ Owner UA ∪ 任一阶段
      #   被指名）∩ 可读活动项目。⚠ 这里**不再**用旧的「同队 + 非本人」推断 —— 真闸门是
      #   ProjectApprover 显式名单（fail-closed，ADR-0029），两处分歧会出现
      #   「列了 3 条、点进去 2 条没权限审」。
      def resource_approval_apps
        @resource_approval_apps ||= begin
          pids = ::Scinote::ElnUi::ResourceApprovalPolicy.approvable_project_ids(@user, @team) &
                 active_readable_project_ids
          if pids.empty?
            []
          else
            ::Scinote::ElnUi::ResourceApplication
              .where(project_id: pids, status: %w[submitted group_approved])
              .order(created_at: :desc)
              .to_a
          end
        end
      end

      def resource_approval(app)
        stage = ::Scinote::ElnUi::ResourceApprovalPolicy.pending_stage(app)
        {
          kind: 'resource_application',
          type: '资源申请',
          title: approval_title(app),
          due: DASH,
          status: stage == 'group' ? '待初审' : '待终审',
          tone: stage == 'group' ? 'primary' : 'purple',
          to: host_routes.eln_res_apply_detail_path(app.no).to_s
        }
      end

      # ② 任务关闭审核（pending）。
      #   口径 = TaskCloseWorkflow.reviewable_project_ids（Project 级 Owner UA，与
      #   reviewer? 闸门逐字同源——判一处，页面和后端不各判一次）。
      #   ⚠ 不放宽到 supervised_by 轨：TaskCloseWorkflow.reviewer? 只认 Owner UA
      #   （OPEN-1 未裁决前的取法），放宽会让工作台列出点下去被 422 的单。
      def task_close_requests
        @task_close_requests ||= begin
          pids = ::Scinote::ElnUi::TaskCloseWorkflow.reviewable_project_ids(@user) &
                 active_readable_project_ids
          if pids.empty?
            []
          else
            ::Scinote::ElnUi::TaskCloseRequest
              .where(status: 'pending')
              .where(my_module_id: ::MyModule.where(archived: false,
                                                    experiment_id: unarchived_experiment_ids.where(project_id: pids).select(:id))
                                            .select(:id))
              .order(submitted_at: :desc)
              .to_a
          end
        end
      end

      def task_close_approval(req)
        mod = req.my_module
        {
          kind: 'task_close',
          type: '任务关闭',
          title: mod&.name.to_s.presence || "任务 ##{req.my_module_id}",
          due: DASH,
          status: '待审核',
          tone: 'warn',
          to: task_url(mod)
        }
      end

      # ③ 到货验收（project_approved 的材料单，累计已验未达申请量）。
      #   口径 = verifiable_project_ids（receipt 阶段名单）∩ 可读活动项目，
      #   收口判据复用 ReceiptVerification.completed_threshold_reached?
      #   （与 ReceiptPendingBook 同一条规则——库房数字说话）。
      #   ⚠ material? 读 item_list JSON（kind=material），只能 Ruby 侧筛。
      def receipt_apps
        @receipt_apps ||= begin
          pids = ::Scinote::ElnUi::ResourceApprovalPolicy.verifiable_project_ids(@user, @team) &
                 active_readable_project_ids
          if pids.empty?
            []
          else
            ::Scinote::ElnUi::ResourceApplication
              .where(project_id: pids, status: 'project_approved')
              .order(created_at: :desc)
              .to_a
              .select { |app| app.material? && !::Scinote::ElnUi::ReceiptVerification.completed_threshold_reached?(app) }
          end
        end
      end

      def receipt_approval(app)
        {
          kind: 'receipt',
          type: '到货验收',
          title: approval_title(app),
          due: DASH,
          status: '待验货',
          tone: 'purple',
          to: host_routes.eln_res_apply_detail_path(app.no).to_s
        }
      end

      def approval_title(app)
        item = Array(app.item_list).first || {}
        name = item.values_at(:name, :title, :label, :resource_name).compact.first.to_s.presence
        return app.no.to_s if name.blank?

        "#{name}（#{app.no}）"
      end

      # ------------------------------------------------------------
      # 4. projects（进行中的项目：参与 ∩ 活动，Q4=A）
      #    与「参与项目」KPI 同一真源 ProjectListScope.participated —— 卡片/列表条数
      #    必须逐位相等（本仓铁律：同一事实单一真源）。
      # ------------------------------------------------------------
      def projects_block
        projects = ::Scinote::ElnUi::ProjectListScope
                   .participated(team: @team, user: @user, view_mode: 'active')
                   .order(Arel.sql('projects.started_at DESC NULLS LAST, projects.id DESC'))
                   .limit(PROJECT_LIMIT)
                   .to_a
        task_counts = my_open_task_counts(projects)
        projects.map { |p| project_row(p, task_counts[p.id].to_i) }
      end

      def project_row(project, task_count)
        status = status_of(project)
        {
          name: project.name.to_s,
          status: status,
          statusLabel: PROJECT_STATUS_LABELS[status] || status,
          role: responsible_project_ids.include?(project.id) ? '负责' : '参与',
          taskSummary: task_count.positive? ? "#{task_count} 个任务待办" : '',
          to: host_routes.project_eln_detail_path(project).to_s
        }
      end

      # 三态推导与 project_list_payload#status_of 逐字同形（原生无状态列，
      # 由 started_at / done_at 推导 —— 两处必须同源码，不许各写一遍）。
      def status_of(project)
        return 'done' if project.respond_to?(:done_at) && project.done_at.present?
        return 'notstarted' if project.respond_to?(:started_at) && project.started_at.blank?

        'active'
      end

      # 我在各项目的未完成任务数（Q9=A 的任务摘要）。
      # ⚠ pluck 后在 Ruby 里 tally：group+count 会被 UA join 放大（同一任务多个角色
      #   指领会重复计数），而这里要的是「任务数」不是「指派行数」。
      def my_open_task_counts(projects)
        return {} if projects.empty?

        ::MyModule
          .joins(:experiment)
          .where(experiments: { project_id: projects.map(&:id), archived: false })
          .where(archived: false, state: 'uncompleted')
          .joins(:user_assignments)
          .where(user_assignments: { user_id: @user.id })
          .distinct
          .pluck('experiments.project_id', :id)
          .each_with_object(Hash.new(0)) { |(pid, _id), acc| acc[pid] += 1 }
      end

      # ------------------------------------------------------------
      # 5. links（「查看全部」：只接已有承载面，Q7=A）
      #    待办区无跨项目任务清单页 ⇒ 不给链接（前端只显示「共 M 条」）。
      # ------------------------------------------------------------
      def links_block
        {
          projectsAll: host_routes.eln_project_list_path(
            filters: { members: [@user.id] }, view_mode: 'active'
          ).to_s,
          resourceApplicationsAll: host_routes.eln_res_center_path(tab: 'apply').to_s
        }
      end

      # ------------------------------------------------------------
      # 6. totals（真实总数，超上限时「共 M 条」用；与列表同口径、同一次会话内各查一次）
      # ------------------------------------------------------------
      def totals_block
        {
          todos: my_open_tasks.count + receipt_todo_apps.size,
          approvals: resource_approval_apps.size + task_close_requests.size + receipt_apps.size,
          projects: ::Scinote::ElnUi::ProjectListScope.participation(team: @team, user: @user)[:participated]
        }
      end

      # receipt_todo_entries 的未截断版（totals 用；memo 防同一请求内跑两遍）
      def receipt_todo_apps
        return @receipt_todo_apps if defined?(@receipt_todo_apps)

        @receipt_todo_apps = ::Scinote::ElnUi::ReceiptPendingBook.for_applicant(@user.id)
                                                                .select { |app| app.project&.team_id == @team.id && !app.project.archived? }
      end

      # ------------------------------------------------------------
      # 状态工具（任务待办的 status 标签用）
      # ------------------------------------------------------------
      # ⚠ final_status_ids 按 **flow** 问而不是按 **状态** 问：flow 只有恒定的几个，
      #   SQL 数从 O(状态数×小组数) 降到 O(flow 数)。
      #   🔴 别下推成「id 不在任何 previous_status_id 里」那种 SQL —— 状态链不保证线性，
      #   同一个 flow 可以挂多条互不相连的状态，「没有后继」的不止一条，而
      #   flow.final_status 只认其中一条 → 完成率被算高（实测 50% 变 100%）。
      def final_status_ids
        @final_status_ids ||= ::MyModuleStatusFlow.all.map { |flow| flow.final_status&.id }.compact.uniq
      end

      def statuses_by_id
        @statuses_by_id ||= statuses_for(my_open_tasks.pluck(:my_module_status_id).compact.uniq)
      end

      def statuses_for(ids)
        ::MyModuleStatus.unscoped.where(id: ids).index_by(&:id)
      end
    end
  end
end
