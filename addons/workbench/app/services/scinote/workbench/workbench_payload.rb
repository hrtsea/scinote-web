# frozen_string_literal: true

# 工作台（Workbench）—— 六块数据装配（REQ-DASHBOARD / SCN-DASH-1~7）
#
# 形状（严格对齐原型 ELN系统-Vue3/src/views/Workbench.vue + src/data/mock.js）：
#   meta:   { greeting, role, updatedAt, notice, statusMachine }
#   kpis:   [{ label, value, trend, tone? }]
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
#           OPEN-WORKBENCH-2（Notification 无细粒度触发源 → notice 只报条数）、
#           OPEN-1（项目负责人双轨：Owner 优先，其次 supervised_by）。
module Scinote
  module Workbench
    class WorkbenchPayload
      # 宿主 UserRole 真名（Owner / User / Technician / Viewer），不认 id。
      OWNER_ROLE_NAME = 'Owner'
      ROLE_ADMIN = '单位管理员'
      ROLE_LEAD = '项目负责人'
      ROLE_MEMBER = '普通组员'
      ROLE_ADMIN_WITH_OWNER = "#{ROLE_ADMIN} · #{OWNER_ROLE_NAME}"

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

      # 计入项目花费的行：物资行恒计，服务行只有 settled 才计（spec L109）。
      COSTABLE_WHERE = "kind = 'material' OR (kind = 'service' AND result_status = 'settled')"
      # 花费拆分只看**消耗方向**（正金额）；还回冲减记在总额里，不当分项。
      CONSUME_ONLY_WHERE = 'amount > 0'

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

      # ------------------------------------------------------------
      # 共用：当前 team 下「我能读」的 project（Canaid 同源同层）
      # ------------------------------------------------------------
      # ⚠ 只读**两处**（scope + ids），supervised_project? 复用同一个 scope，
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
        return ROLE_ADMIN_WITH_OWNER if owner_user?
        return ROLE_LEAD if supervised_project?

        ROLE_MEMBER
      end

      # ⚠ users 表没有 role/admin 列（项目铁律），Owner 只能从
      #   UserAssignment → UserRole 反查；命中任意一条 Owner 赋值即算。
      def owner_user?
        return false if @user.nil?

        ::UserAssignment.where(user_id: @user.id)
                        .joins(:user_role)
                        .where(user_roles: { name: OWNER_ROLE_NAME })
                        .exists?
      end

      # OPEN-1 未决，宽口径：任一可读 project 的 supervised_by 是自己。
      def supervised_project?
        return false if @user.nil?

        readable_projects.where(supervised_by_id: @user.id).exists?
      end

      # ⚠ 原生 Notification 只有 GeneralNotification / ActivityNotification 两态，
      #   没有细粒度触发源分类（OPEN-WORKBENCH-2）→ 只报条数，不编细目。
      def notice_value
        count = unread_notification_count
        count.to_i.zero? ? '暂无未读通知' : "#{count} 条未读通知"
      end

      def unread_notification_count
        ::Notification.where(recipient_type: 'User', recipient_id: @user.id, read_at: nil).in_app.count
      end

      def status_machine_value
        ::MyModuleStatus.order(:id).pluck(:name).join(' / ')
      end

      # ------------------------------------------------------------
      # 2. kpis（私有化部署不输出云版 Token 卡 → 只出 3 张）
      # ------------------------------------------------------------
      def kpis_block
        [groups_kpi, tasks_kpi, cost_kpi]
      end

      # ① 小组数 = 当前 team 的小组数；trend = 覆盖组员人数（真数）
      def groups_kpi
        groups = team_user_groups
        { label: '小组数', value: groups.size.to_s,
          trend: groups.empty? ? '' : "覆盖 #{group_member_count(groups)} 名组员" }
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
      def tasks_kpi
        { label: '项目任务', value: team_my_modules.count.to_s,
          trend: status_counts.first(TASK_TREND_LIMIT).map { |status_id, num|
                   status = status_for(status_id)
                   next nil if status.nil?

                   "#{status.name} #{num}"
                 }.compact.join(' · ') }
      end

      # ③ 项目总花费 = 消耗明细按可读 project 聚合，求和交给库算。
      def cost_kpi
        total = cost_total
        { label: '项目总花费', value: money(total), trend: cost_trend(total) }
      end

      # ⚠ amount **带符号**（与 Ledger 同源：正=消耗、负=还回），直接 sum 就是净花费，
      #   取绝对值会把「还回冲减」变成「额外增加」。
      def cost_total
        cost_scope.where(COSTABLE_WHERE).sum(:amount)
      end

      def cost_trend(total)
        return '' if total.to_d.zero?

        parts = %w[material service].map do |kind|
          sum = cost_scope.where(kind: kind).where(CONSUME_ONLY_WHERE).sum(:amount)
          next nil if sum.to_d.zero?

          "#{kind == 'material' ? '材料' : '服务'} #{pct(sum, total)}%"
        end.compact
        return '' if parts.empty?

        parts.join(' · ')
      end

      # ⚠ 跨 addon 依赖：消耗明细表在 eln_ui 上。两个 addon 同为 Gemfile 里的 path gem，
      #   永远一起挂载 —— 取不到是启动期的事，不是请求期兜一层 `rescue NameError → nil`。
      def cost_scope
        ::Scinote::ElnUi::ConsumeRecord.where(project_id: readable_project_ids)
      end

      def pct(part, total)
        ((part.to_d * 100) / total.to_d).round
      end

      # ⚠ 别换成 number_to_currency：它恒输出两位小数（¥300.00），而工作台口径是
      #   **整数不带小数**（¥300）、只有真有零头才补两位（¥300.50）——改了就是
      #   UI 全线变丑 + 测试 assert_equal '¥300' 直接红。
      def money(value)
        v = value.to_d
        int = v.round.to_i
        formatted = int == v ? int.to_s : format('%.2f', v)
        "¥#{formatted.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end

      # ------------------------------------------------------------
      # 3. todos（个人待办，最多 6 条）
      # ------------------------------------------------------------
      def todos_block
        approvals = pending_approvals.first(TODO_APPROVAL_SLOTS).map { |app| approval_todo(app) }
        room = [TODO_LIMIT - approvals.size, 0].max
        mine = my_open_modules.first(room).map { |mod| module_todo(mod) }
        (approvals + mine).first(TODO_LIMIT)
      end

      # ① 待我审的资源申请：同队 + 非本人（审批口径与 ResourceApplicationWorkflow 同源）。
      def pending_approvals
        ::Scinote::ElnUi::ResourceApplication.for_team(@team)
                                             .where(status: %w[submitted group_approved])
                                             .where.not(requestor_id: @user.id)
                                             .order('eln_ui_resource_applications.created_at' => :desc)
                                             .to_a
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

      # ② 我的进行中任务（MyModule 经 UserAssignment 指向我）
      def my_open_modules
        team_my_modules.joins(:user_assignments)
                       .where(user_assignments: { user_id: @user.id })
                       .distinct
                       .order(created_at: :desc)
                       .to_a
      end

      def module_todo(mod)
        {
          type: '任务',
          title: mod.name.to_s,
          due: due_label(mod),
          status: mod.my_module_status&.name.to_s.presence || DASH,
          tone: mod.my_module_status&.final_status? ? 'primary' : 'warn'
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
        ::MyModuleStatus.unscoped.find_by(id: status_id)
      end

      # 色值由**本服务**下发（组件内不硬编颜色）；原生浅色（如 Not started 的
      # #FFFFFF）白底上不可见 → 降级中性灰。
      def bar_color(status)
        return NEUTRAL_BAR_COLOR if status.light_color?

        status.color.to_s.strip.presence || NEUTRAL_BAR_COLOR
      end

      def final_status_ids
        ::MyModuleStatus.unscoped.select(&:final_status?).map(&:id)
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
      def member_task_stats(user_ids)
        assignments = ::UserAssignment.where(assignable_type: 'MyModule')
                                      .where(assignable_id: team_my_modules.select(:id))
                                      .where(user_id: user_ids)
        return [0, 0] if assignments.empty?

        mods = team_my_modules.where(id: assignments.pluck(:assignable_id)).index_by(&:id)
        finals = final_status_ids
        [assignments.size,
         assignments.count { |a| finals.include?(mods[a.assignable_id]&.my_module_status_id) }]
      end

      # ------------------------------------------------------------
      # 6. entries（快捷入口：只发真源可达的宿主路由）
      # ------------------------------------------------------------
      # ⚠ 原型的「新建实验任务」「报表中心」宿主没有承载面 → **不输出**（显式留白）。
      def entries_block
        helpers = ::Rails.application.routes.url_helpers
        [
          { label: '项目管理', to: helpers.eln_project_list_path.to_s },
          { label: '资源中心', to: helpers.eln_res_center_path.to_s }
        ]
      end
    end
  end
end
