# frozen_string_literal: true

# 工作台（Workbench）—— 六块数据装配（REQ-DASHBOARD / SCN-DASH-1~7）
#
# 形状（严格对齐原型 ELN系统-Vue3/src/views/Workbench.vue + src/data/mock.js）：
#   meta:   { greeting, role, updatedAt, notice, statusMachine }
#   kpis:   [{ label, value, trend, to? / anchor?, tone? }]
#   todos:  [{ type, title, due, status, tone? }]
#   dist:   [{ label, num, color }]
#   groups: [{ name, leader, rate, tone? }]
#   entries:[{ label, to }]
#
# 五条口径：
#   1. **全部实时读库**：不做缓存快照、不建中间表。
#   2. **状态一律用数据库真名**：MyModule 走原生动态状态流 `my_module_statuses`。
#      颜色由本服务下发（组件内不硬编色值）。
#   3. **取不到就显式留白**：原生无承载面的概念给空数组 / '—'，不编演示值。
#   4. **链接由本服务下发**：`entries[].to` 从宿主 `Rails.application.routes`
#      的真实 path helper 取（项目铁律：前端不写死宿主路由）。
#   5. **四角色差异化本轮不做**：原型画布只承载「项目负责人」单视图（OPEN-WORKBENCH-4）。
#
# 权限模型（access_control D8 同源同层）：沿用原生 Canaid，不新建权限位。
#   「当前用户能读的 project」= ::Project.readable_by_user(user) ∩ 当前 team。
#
# ⚠ 未决项：OPEN-WORKBENCH-1（UserGroup 无 leader 承载列 → `leader` 恒 '—'）、
#           OPEN-WORKBENCH-2（Notification 无细粒度触发源 → notice 只报条数）。
# ✅ 已闭环：OPEN-1（项目负责人双轨）—— 2026-10-05 落成 `project_lead?`：
#           supervised_by 或 Project 级 Owner 命中任一即算（生产实测两条轨道各有一半人）。
# ✅ 已闭环（V1.27）：第三张 KPI 卡由「项目总花费」改为「参与项目」。参与/负责口径与
#           项目列表页**共用单一真源** `Scinote::ElnUi::ProjectListScope` —— 卡片数字必须
#           逐位等于点进去列表页筛出来的条数，两侧同一段可变代码才守得住该不变式。
module Scinote
  module Workbench
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

      # 条形图色降级：原生「Not started」的色是 #FFFFFF，画在白底卡片上等于隐形。
      NEUTRAL_BAR_COLOR = '#B0B0B0'
      # 小组完成率达标线（≥80% = done，<80% = warn）
      RATE_DONE_THRESHOLD = 80

      # 个人待办上限（画布只给了 3 条的高度，超过会让版式塌）
      TODO_LIMIT = 6
      TODO_APPROVAL_SLOTS = 3

      # dist 条形图最多画几条 + kpis[项目任务].trend 最多列几个分项（口径同一处取数）。
      DIST_LIMIT = 6
      TASK_TREND_LIMIT = 3

      # 无真源时的显式留白（不是演示文案）
      DASH = '—'

      # 「小组数」卡页内锚点的目标 DOM id（= 右列「小组汇总」卡的 id，Q2 裁决）。
      #   ⚠ 由 **payload 下发**，不在组件里硬编 —— 与「前端不写死宿主路由」同一条铁律：
      #   跳转目标属于「服务端知道、前端不该猜」的信息。
      #   ⚠ 原型 `ELN系统-prototype.html` 里同一张卡的 id 必须与这个值一致
      #   （改这里要同步改原型，否则三方对齐断链）。
      GROUPS_ANCHOR_ID = 'eln-wb-groups'

      # ------------------------------------------------------------
      # 🔴 V1.27：本类**不再输出任何花费卡**（第三张 KPI 卡已由「项目总花费」改为「参与项目」）。
      #
      #   历史（V1.25）：这里原先持有两条花费口径常量（`COSTABLE_WHERE` / `CONSUME_ONLY_WHERE`），
      #   它们是 eln_ui 侧同一件事的**第二份定义**（漏了设备模板剔除、范围也不同），故被删除，
      #   统一改调 `Scinote::ElnUi::ProjectCosts`（单一真源）。
      #   V1.27 又把「项目总花费」整张卡连同其取数私有方法一并删除 —— 花费展示完整地留在资源中心
      #   花费页签，工作台不再复述。
      #
      #   🔴🔴 但**千万别顺手把下面这些也删了**（删了当场 500 或破坏别处）：
      #     · `WorkbenchPayload#pct` —— 本文件**小组完成率**在用（group_row），与花费无关；
      #     · `Scinote::ElnUi::ProjectCosts` / `Scinote::ElnUi::MoneyFormat` —— 资源中心
      #       花费页签（res_center_payload）、项目详情花费面板（project_detail_payload#cost_block）、
      #       `Scinote::ElnUi::EquipmentTemplateFilter` 都还在用；
      #     · 前端 mock.js 里资源中心/项目详情用的花费数据。
      #   「工作台不再用」≠「没人用」—— 删之前先 grep 全仓。
      # ------------------------------------------------------------

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
          meta: {
            greeting: greeting_value,
            role: role_value,
            updatedAt: "数据更新于 #{Time.current.strftime('%H:%M')}",
            notice: notice_value,
            statusMachine: status_machine_value
          },
          kpis: kpis_block,
          todos: todos_block,
          dist: dist_block,
          groups: groups_block,
          entries: entries_block
        }
      end

      private

      # 宿主真实 path helper 的入口（entries 快捷入口 + kpis 下钻目标共用）。
      #   ⚠ 必须真的存在：写错 helper 名 = 加载期 NoMethodError，
      #   这是好事（当场炸），别再包一层 rescue 把它变成静默兜底 ——
      #   隔壁 notifications_payload 就因为这么干，把 `eln_res_apply_path`
      #   这个错误名字藏了很久（见该文件 subject_url 的注释）。
      def host_routes
        @host_routes ||= ::Rails.application.routes.url_helpers
      end

      # ------------------------------------------------------------
      # 共用：当前 team 下「我能读」的 project（Canaid 同源同层）
      # ------------------------------------------------------------
      # ⚠ 只读**两处**（scope + ids），project_lead? / project_owner? 复用同一个 scope，
      #   不再各自重算一遍 `readable_by_user ∩ team`。
      def readable_projects
        @readable_projects ||= ::Project.readable_by_user(@user).where(team_id: @team.id)
      end

      def readable_project_ids
        @readable_project_ids ||= readable_projects.pluck(:id)
      end

      # 该 team 可读范围内的全部 MyModule（工作台所有「任务」口径的底座）
      def team_my_modules
        ::MyModule.where(experiment_id: ::Experiment.where(project_id: readable_project_ids).select(:id))
      end

      # ------------------------------------------------------------
      # 1. meta
      # ------------------------------------------------------------
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
      #   原写法是
      #     UserAssignment.where(user_id:).joins(:user_role).where(user_roles: { name: 'Owner' }).exists?
      #   —— **不限 assignable_type**，于是「在某个 Project / Experiment / MyModule 上
      #   挂着 Owner」也被算作单位管理员。
      #   生产实测（4 个用户的库）：3 个被贴上「单位管理员 · Owner」，
      #   而全库 **Team 级 Owner 只有 1 条**。
      #   典型样本 hrtsea@qq.com：Team 级角色是 `User`，Owner 命中全是
      #   {Experiment: 96, MyModule: 50, Project: 4} —— 他其实是 203 个项目的负责人。
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
      #   ⚠ 双轨是**并列**不是「Owner 优先」：两者都指向同一档展示文案，
      #     分优先级只会多一次查询，改变不了任何人的标签。
      def project_lead?
        return false if @user.nil?

        readable_projects.where(supervised_by_id: @user.id).exists? || project_owner?
      end

      # ⚠ 用子查询而不是 `assignable_id: readable_project_ids`：
      #   后者会把全部 id 拼成 IN 列表（生产实测单用户可读项目可达 288 个）。
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

      # 🔴 V1.25：未读数走 **eln_ui 的单一真源**（`NotificationsPayload.scope_for`）——
      #   宿主顶栏徽标（navigations_controller.rb:103）与通知中心列表用的是同一个
      #   `notifications.in_app.where(read_at: nil)` 口径。三处必须是同一个数，
      #   否则「铃铛显示 3、点开只有 1 条」这个 bug 会换个地方复发。
      #   ⚠ 旧写法用 `recipient_type/recipient_id` 明文条件且不筛 in_app ——
      #   多态列名写死是脆的（写错静默查空），`in_app` 漏筛会把 hide_in_app 的通知也数进去。
      def unread_notification_count
        ::Scinote::ElnUi::NotificationsPayload.unread_count_for(@user)
      end

      def status_machine_value
        ::MyModuleStatus.order(:id).pluck(:name).join(' / ')
      end

      # ------------------------------------------------------------
      # 2. kpis（私有化部署不输出云版 Token 卡 → 只出 3 张）
      #
      # V1.27 三张卡：小组数（页内锚点）/ 项目任务（项目列表页）/ **参与项目**（成员筛选后的
      #   项目列表页）。第三张原为「项目总花费」，已删除。
      #
      # 🔴 V1.25：每张卡都带**下钻目标**（spec SCN-DASH-8）。两个字段互斥：
      #   `to`     = 宿主真实路由（整页跳转），由宿主 path helper 生成；
      #   `anchor` = 本页内目标卡的 DOM id（页内滚动 + 高亮），不下发 '#' 前缀。
      #   原生没有承载面的概念**一律不给 target**（拿到假 punch 前端照样跳不动），
      #   前端据此决定「可点 / 不可点」，不再由自己去猜路由。
      # ------------------------------------------------------------
      def kpis_block
        [groups_kpi, tasks_kpi, participation_kpi]
      end

      # ① 小组数 = 当前 team 的小组数；trend = 覆盖组员人数（真数）
      #
      # 下钻 = **页内锚点**到右下「小组汇总」卡（本轮 Q2 裁决）。
      #   ⚠ 为什么不是新建「小组列表页」：原生没有跨项目小组清单的承载面，
      #     而同页右下角本来就有一张小组汇总 —— 跳走反而丢上下文（Q1：只接已存在的承载面）。
      def groups_kpi
        groups = team_user_groups
        { label: '小组数', value: groups.size.to_s,
          trend: groups.empty? ? '' : "覆盖 #{group_member_count(groups)} 名组员",
          anchor: GROUPS_ANCHOR_ID }
      end

      def team_user_groups
        @team.user_groups
      end

      def group_member_count(groups)
        ::UserGroupMembership.where(user_group_id: groups).distinct.pluck(:user_id).size
      end

      # ② 项目任务 = 该 team 可读 project 下的 MyModule 总数
      #    trend 取**数量最多的前 3 个真实状态名**（不翻译、不猜语义），
      #    逐条与 dist 的条形标签对得上，不出现靠正则猜出来的「已完成 N」假数。
      #
      # 下钻 = 项目列表页（Q3 裁决）：原生任务始终挂在某个实验下，**没有跨项目的
      #   任务清单页**，所以这里给的是四级链路的入口（REQ-PROJ-LIST：
      #   项目列表 → 项目详情 → 实验详情 → 任务详情）。
      #   「跨项目任务列表页」另立 issue（宿主无承载面时不编页面，Q1）。
      def tasks_kpi
        { label: '项目任务', value: team_my_modules.count.to_s,
          trend: status_counts.first(TASK_TREND_LIMIT).map { |status_id, num|
                   status = status_for(status_id)
                   next nil if status.nil?

                   "#{status.name} #{num}"
                 }.compact.join(' · '),
          to: host_routes.eln_project_list_path.to_s }
      end

      # ③ 参与项目 = 我在本单位的**参与项目数**；trend = 「其中我负责 M 个」。
      #
      # 口径（用户拍板，勿改）单一真源 = `Scinote::ElnUi::ProjectListScope`
      #   （与项目列表页 controller 同一个类 —— 不再是「两处各写一遍 scope」，
      #    那正是本项目两次出事的形态）：
      #     参与 = 项目列表 scope（team ∩ template[false,nil] ∩ readable ∩ active）
      #            ∩ 我的 Project 级 UserAssignment；
      #     负责 = projects.supervised_by_id==我 或 我在该项目上有 Project 级 Owner 角色的 UA
      #            （双轨并集，与 project_lead? / project_owner? 同语义，由真源类复用求值）。
      #
      # 下钻 = 宿主项目列表页，**带成员筛选** + **显式 view_mode=active**：
      #   · 不带成员筛选 → 卡片数字（参与数）与点进去的列表（可读全量）会对不上，
      #     这正是本卡存在的意义（卡片数字 ≡ 点进去筛出来的条数）。
      #   · 显式带 view_mode=active：卡片只统计**活动**项目，把口径写进 URL 才自描述 ——
      #     否则两侧一致就依赖「列表页默认视图恰好是 active」这个隐含约定，将来谁把默认
      #     改成全量就静默漂开（同一件事两份定义的复发形态）。
      #   ⚠ URL 由宿主 path helper 生成，**不手写字符串路径**（路由改名自动跟随）。
      #
      # 「负责数」**不给下钻**：宿主没有「我负责的项目列表」承载面（列表页只按成员筛，
      #   没有「负责人=我」这一轴），所以 trend 是**纯文本**、整卡只给一个 to，不给 anchor。
      #   ⚠ M=0 时 trend 必须是**空串**（不是「其中我负责 0 个」）：0 是噪声，会让副行
      #     看起来像有信息（用户明确要求）。
      def participation_kpi
        stats = ::Scinote::ElnUi::ProjectListScope.participation(team: @team, user: @user)
        responsible = stats[:responsible].to_i

        {
          label: '参与项目',
          value: stats[:participated].to_i.to_s,
          trend: responsible.zero? ? '' : "其中我负责 #{responsible} 个",
          to: host_routes.eln_project_list_path(
            filters: { members: [@user.id] }, view_mode: 'active'
          ).to_s
        }
      end

      # ⚠ 保留下方 `pct`（V1.27 删花费卡时**绝不能跟着删**）：它是**小组完成率**在用的
      #   百分比算法（见 group_row → rate / tone），与花费无关。删它 = 小组完成率当场 500。
      def pct(part, total)
        ((part.to_d * 100) / total.to_d).round
      end

      # ------------------------------------------------------------
      # 3. todos（个人待办，最多 6 条）
      # ------------------------------------------------------------
      def todos_block
        approvals = pending_approvals(TODO_APPROVAL_SLOTS).map { |app| approval_todo(app) }
        room = [TODO_LIMIT - approvals.size, 0].max
        (approvals + module_todos(room)).first(TODO_LIMIT)
      end

      # ① 待我审的资源申请：同队 + 非本人（审批口径与 ResourceApplicationWorkflow 同源）。
      #    ⚠ limit 交给 SQL：先 .to_a 再 .first(N) 会把全队申请全捞进内存再砍。
      def pending_approvals(limit)
        ::Scinote::ElnUi::ResourceApplication.for_team(@team)
                                             .where(status: %w[submitted group_approved])
                                             .where.not(requestor_id: @user.id)
                                             .order(created_at: :desc)
                                             .limit(limit)
      end

      def approval_todo(app)
        {
          type: '资源申请',
          title: approval_title(app),
          # 资源申请单没有「截止日」列 → 显式留白（OPEN-WORKBENCH-3）
          due: DASH,
          status: app.submitted? ? '待初审' : '待终审',
          tone: app.submitted? ? 'primary' : 'purple'
        }
      end

      def approval_title(app)
        item = Array(app.item_list).first || {}
        name = item.values_at(:name, :title, :label, :resource_name).compact.first.to_s.presence
        return app.no.to_s if name.blank?

        "#{name}（#{app.no}）"
      end

      # ② 我的任务（MyModule 经 UserAssignment 指向我）
      #    ⚠ limit 交给 SQL：默认场景我的任务有几十条，而画布只放得下 6 条。
      def my_open_modules(limit)
        team_my_modules.joins(:user_assignments)
                       .where(user_assignments: { user_id: @user.id })
                       .distinct
                       .order(created_at: :desc)
                       .limit(limit)
      end

      # ⚠ 「次次问 ORM」在这里是纯浪费：`my_module_status` 还好预加载，
      #   但 `final_status?` 是**查询方法不是关联** —— includes 救不了它，
      #   实测 72 条任务在这段发 200+ 条 SQL。
      #   正解：一次性取任务 → 一次性补齐状态 → 拿 id 集合做包含判断。
      def module_todos(limit)
        return [] if limit.to_i.zero?

        mods = my_open_modules(limit).to_a
        return [] if mods.empty?

        statuses = statuses_for(mods.map(&:my_module_status_id).compact.uniq)
        finals = final_status_ids
        mods.map { |mod| module_todo(mod, statuses[mod.my_module_status_id],
                                     finals.include?(mod.my_module_status_id)) }
      end

      def module_todo(mod, status, final)
        {
          type: '任务',
          title: mod.name.to_s,
          due: due_label(mod),
          status: status&.name.to_s.presence || DASH,
          tone: final ? 'primary' : 'warn'
        }
      end

      # due_date 是真列（my_modules.due_date），有值才写，没值就 '—'
      def due_label(mod)
        return DASH if mod.due_date.blank?

        mod.due_date.strftime('%m-%d')
      end

      # ------------------------------------------------------------
      # 4. dist（任务状态分布：真状态名 + 真色，按数量降序取前 6）
      # ------------------------------------------------------------
      # ⚠ 只有一条 SQL 分组 + 一次取色；不再内部携带 ORM 实例
      #   （payload 装配不该知道 MyModuleStatus 的内部形状）。
      def dist_block
        status_counts.first(DIST_LIMIT).map do |status_id, num|
          status = status_for(status_id)
          next nil if status.nil?

          { label: status.name.to_s, num: num, color: bar_color(status) }
        end.compact
      end

      # 状态分布：tasks_kpi 的 trend 与 dist_block 是**同一份**分组结果，只查一次。
      # ⚠ 分组键可能是 nil（任务没挂状态）→ 一律按「查不到」跳过，
      #   **不能用 find**：find(nil) 直接抛 RecordNotFound，整个 payload 500。
      def status_counts
        @status_counts ||= team_my_modules.group(:my_module_status_id).count
                                          .sort_by { |_, num| -num }
      end

      def status_for(status_id)
        statuses_by_id[status_id]
      end

      # dist / tasks_kpi 取的都出自同一份 status_counts → 一次查完。
      #   ⚠ 别在 map 里逐条 find_by：每多一种状态就多一条 SQL，且两处各雷一遍。
      def statuses_by_id
        @statuses_by_id ||= statuses_for(status_counts.map(&:first).compact.uniq)
      end

      def statuses_for(ids)
        ::MyModuleStatus.unscoped.where(id: ids).index_by(&:id)
      end

      # 色值由**本服务**下发（组件内不硬编颜色）；原生浅色（如 Not started 的
      # #FFFFFF）白底上不可见 → 降级中性灰。
      def bar_color(status)
        return NEUTRAL_BAR_COLOR if status.light_color?

        status.color.to_s.strip.presence || NEUTRAL_BAR_COLOR
      end

      # ⚠ final_status_ids 是小组完成率的判定基准，必须 memo —— 每个小组都要用它。
      #   原生 MyModuleStatus#final_status? = `my_module_status_flow.final_status == self`，
      #   而 MyModuleStatusFlow#final_status 又是一次 left_outer_joins + find_by ——
      #   **每条状态两次查询**；外面套 select(&:final_status?) 就是全表逐条问 ORM。
      #   改成按 **flow** 问而不是按 **状态** 问：flow 只有恒定的几个，SQL 数从 O(状态数×小组数)
      #   降到 O(flow 数)。
      #
      #   🔴 别下推成「id 不在任何 previous_status_id 里」那种 SQL —— 看着优雅，实际错：
      #      它成立的前提是状态链线性（一条最多一个后继）。实测不成立：同一个 flow 里可以挂
      #      多条**互不相连**的状态（本仓库 test 工厂 make_status! 就是这么造的），
      #      此时「没有后继」的不止一条，而 flow.final_status 只认其中一条
      #      → 完成率被算高（用例实测：50% 直接变 100%）。
      #   ⚠ workbench_test 有一条用例盯着「批量版 == 逐条版」，改坏会立刻红。
      def final_status_ids
        @final_status_ids ||= ::MyModuleStatusFlow.all.map { |flow| flow.final_status&.id }.compact.uniq
      end

      # ------------------------------------------------------------
      # 5. groups（小组汇总；小组为空 → 空数组，绝不回落演示文案）
      # ------------------------------------------------------------
      def groups_block
        team_user_groups.map { |group| group_row(group) }
      end

      def group_row(group)
        user_ids = ::UserGroupMembership.where(user_group_id: group.id).distinct.pluck(:user_id)
        total, done = member_task_stats(user_ids)
        rate = total.to_d.zero? ? DASH : "#{pct(done, total)}%"
        {
          name: group.name.to_s,
          # ⚠ 原生 UserGroup 只有 (name/team_id/created_by_id/last_modified_by_id)，
          #   没有组长承载列（OPEN-WORKBENCH-1）→ 显式 '—'，不猜不编。
          leader: DASH,
          rate: rate,
          tone: rate == DASH ? nil : (pct(done, total) >= RATE_DONE_THRESHOLD ? 'done' : 'warn')
        }
      end

      # 组内组员「被指派任务」的完成态占比
      # ⚠ 两次 pluck 完事，不逐条查：assignment 只需要 id，任务只需要 (id, status_id)。
      #    分子/分母按**指派行**计（同一任务被多个组员指派算多次），保持原口径。
      def member_task_stats(user_ids)
        assignable_ids = ::UserAssignment.where(assignable_type: 'MyModule')
                                         .where(assignable_id: team_my_modules.select(:id))
                                         .where(user_id: user_ids)
                                         .pluck(:assignable_id)
        return [0, 0] if assignable_ids.empty?

        finals = final_status_ids
        status_by_mod = team_my_modules.where(id: assignable_ids.uniq).pluck(:id, :my_module_status_id).to_h
        [assignable_ids.size,
         assignable_ids.count { |mod_id| finals.include?(status_by_mod[mod_id]) }]
      end

      # ------------------------------------------------------------
      # 6. entries（快捷入口：只发真源可达的宿主路由）
      # ------------------------------------------------------------
      # ⚠ 原型的「新建实验任务」「报表中心」宿主没有承载面 → **不输出**（显式留白）。
      def entries_block
        [
          { label: '项目管理', to: host_routes.eln_project_list_path.to_s },
          { label: '资源中心', to: host_routes.eln_res_center_path.to_s }
        ]
      end
    end
  end
end
