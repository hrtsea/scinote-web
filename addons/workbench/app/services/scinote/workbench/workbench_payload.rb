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
# 五条口径（本轮全部按此落地，任何一条都**不许回落演示文案**）：
#   1. **全部实时读库**：不做任何缓存快照、不建中间表，每次请求重查。
#   2. **状态一律用数据库真名**：MyModule 走原生动态状态流 `my_module_statuses`
#      （不是原型的「待接收/进行中/提交完成申请/待审核/已关闭」演示标签）。
#      颜色由本服务下发（组件内不硬编色值；原生状态色是高对比度色时降级为中性灰）。
#   3. **取不到就显式留白**：原生无承载面的概念给空数组 / '—'，不编「张负责人」、
#      「¥86.4万」「62%」「18 天耗尽」这类画布演示值。
#   4. **链接由本服务下发**：entries[].to 走宿主 `Rails.application.routes`
#      的真实 path helper 取出来（后端是唯一知道宿主路由表的一层），
#      前端绝不写死宿主路由（项目铁律）。
#   5. **四角色差异化本轮不做**：原型画布只承载「项目负责人」单视图，没有承载面
#      就不擅自编 SCN-DASH-1/2/4 的布局 —— 记为 OPEN-WORKBENCH-* 回报。
#
# 权限模型（access_control D8 同源同层）：沿用原生 Canaid，不新建权限位。
#   「当前用户能读的 project」= ::Project.readable_by_user(user) ∩ 当前 team；
#   其余（小组、通知、资源申请、消耗明细）全部挂在这批 project 之下。
#
# ⚠ 未决项（不在本服务内收窄）：
#   · OPEN-WORKBENCH-1：小组组长 —— UserGroup 只有 (name/team_id/created_by_id)，
#     没有 leader 承载列，这里给 '—'，不猜。
#   · OPEN-WORKBENCH-2：通知触发源明细 —— 原生 Notification 只有 type
#     (GeneralNotification / ActivityNotification) 两态，没有「任务指派/驳回/审核
#     通过/资源申请结果/评论/Token 预警/AI 完成」的细粒度分类，所以 notice 只报
#     未读条数，不编细目。
#   · OPEN-1（项目负责人双轨）：这里按宽口径①Owner ②任一可读 project 的
#     supervised_by ③其他，未收窄。
module Scinote
  module Workbench
    class WorkbenchPayload
      # 宿主 UserRole 真名（Owner / User / Technician / Viewer），不认 id。
      OWNER_ROLE_NAME = 'Owner'
      ROLE_ADMIN = '单位管理员'
      ROLE_LEAD = '项目负责人'
      ROLE_MEMBER = '普通组员'

      # 角色徽章文案：**宿主角色名**拼在后面，避免徽章只写「管理员」这种泛化词。
      ROLE_ADMIN_WITH_OWNER = "单位管理员 · #{OWNER_ROLE_NAME}"

      # 完成态兜底判定：原生 MyModuleStatus 只有 final_status? 一个谓词，
      # 兜底正则只在中国人自定义状态名（「已完成 / 已关闭 / 完结」）上生效。
      FINAL_STATUS_FALLBACK_RE = /complet|finish|done|close|已关闭|已完成|完结/i.freeze

      # 条形图色降级：原生「Not started」的色是 #FFFFFF，画在白底卡片上等于隐形。
      NEUTRAL_BAR_COLOR = '#B0B0B0'
      # 小组完成率达标线（≥80% = done，<80% = warn；无数据 = 不打分）
      RATE_DONE_THRESHOLD = 80

      # 个人待办上限（画布只给了 3 条的高度，超过会让版式塌）
      TODO_LIMIT = 6
      TODO_APPROVAL_SLOTS = 3

      # dist 条形图最多画几条 + kpis[项目任务].trend 最多列几个分项。
      # ⚠ 两个值故意**分开**（条形图最多 6 条、trend 文案最多 3 项免溢出），
      #   但它们读的是同一个 status_distribution，口径永远一致。
      DIST_LIMIT = 6
      TASK_TREND_LIMIT = 3

      # 无真源时的显式留白（不是演示文案）
      DASH = '—'

      class << self
        # 入口：controller 注入 user + team（minitest 里也可以直接 new(...).call，
        # 不挑场景 —— 与 eln_ui 各 Payload 同一条约定）。
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
      def readable_project_ids
        @readable_project_ids ||= begin
          scope = ::Project.readable_by_user(@user)
          scope = scope.where(team_id: @team.id) if @team&.respond_to?(:id) && @team.id
          scope.pluck(:id)
        rescue StandardError
          []
        end
      end

      # 该 team 可读范围内的全部 MyModule（工作台所有「任务」口径的底座）
      def team_my_modules
        @team_my_modules ||=
          ::MyModule.where(experiment_id: ::Experiment.where(project_id: readable_project_ids).select(:id))
      end

      # ------------------------------------------------------------
      # 1. meta
      # ------------------------------------------------------------
      def meta_block
        {
          greeting: greeting_value,
          role: role_value,
          updatedAt: "数据更新于 #{Time.current.strftime('%H:%M')}",
          notice: notice_value,
      # 状态机真名（条形图卡头）：下发**数据库里真实的状态名**，
      # 组件不再硬编原型的五个演示标签。
      statusMachine: status_machine_value
        }
      end

      def greeting_value
        "#{period_word}好，#{@user.full_name}"
      end

      def period_word
        hour = Time.current.hour
        return '凌晨' if hour < 6
        return '上午' if hour < 12
        return '下午' if hour < 18

        '晚上'
      end

      # 三档宽口径（OPEN-1 未决，不擅自收窄）：
      #   ① 宿主角色 Owner            → 单位管理员 · Owner
      #   ② 任一可读 project 负责人    → 项目负责人
      #   ③ 其他                       → 普通组员
      # ⚠ 小组组长（UserGroup 无 leader 列）本轮不判定 —— OPEN-WORKBENCH-1。
      def role_value
        return ROLE_ADMIN_WITH_OWNER if owner_user?
        return ROLE_LEAD if supervised_project?

        ROLE_MEMBER
      end

      # ⚠ users 表没有 role/admin 列（项目铁律 §1），Owner 只能从
      #   UserAssignment → UserRole 反查；命中任意一条 Owner 赋值即算，宽口径。
      def owner_user?
        return false if @user.nil?

        ::UserAssignment.where(user_id: @user.id)
                        .joins(:user_role)
                        .where(user_roles: { name: OWNER_ROLE_NAME })
                        .exists?
      end

      def supervised_project?
        return false if @user.nil?

        scope = ::Project.readable_by_user(@user)
        scope = scope.where(team_id: @team.id) if @team&.respond_to?(:id) && @team.id
        scope.where(supervised_by_id: @user.id).exists?
      rescue StandardError
        false
      end

      # 未读站内信条数（原生 Notification，recipient 是 polymorphic）。
      # ⚠ 原生 Notification 只有 GeneralNotification / ActivityNotification 两态，
      #   没有细粒度触发源分类（OPEN-WORKBENCH-2）→ 只报条数，不编细目。
      def notice_value
        count = unread_notification_count
        count.to_i.zero? ? '暂无未读通知' : "#{count} 条未读通知"
      end

      def unread_notification_count
        return 0 if @user.nil?

        base = ::Notification.where(recipient_type: 'User', recipient_id: @user.id, read_at: nil)
        begin
          base.in_app.count
        rescue StandardError
          base.count
        end
      end

      def status_machine_value
        ::MyModuleStatus.order(:id).pluck(:name).join(' / ')
      rescue StandardError
        ''
      end

      # ------------------------------------------------------------
      # 2. kpis（画布 4 卡；云版 Token 卡私有化部署不输出 → 只出 3 张）
      # ------------------------------------------------------------
      def kpis_block
        [groups_kpi, tasks_kpi, cost_kpi].compact
      end

      # ① 小组数 = 当前 team 的小组数；trend = 覆盖组员人数（真数）
      def groups_kpi
        groups = team_user_groups
        trend = groups.empty? ? '' : "覆盖 #{group_member_count(groups)} 名组员"
        { label: '小组数', value: groups.size.to_s, trend: trend }
      end

      def team_user_groups
        return [] if @team.nil? || !@team.respond_to?(:user_groups)

        @team.user_groups.to_a
      rescue StandardError
        []
      end

      def group_member_count(groups)
        return 0 if groups.empty?

        ::UserGroupMembership.where(user_group_id: groups.map(&:id)).distinct.count(:user_id)
      end

      # ② 项目任务 = 该 team 可读 project 下的 MyModule 总数
      #
      # ⚠🔴 口径修正（必修）：trend **不能直接取 status_distribution 的分项**：
      #    dist 是按 `my_module_status.name` 聚合的（真状态名），而这里必须和它
      #    **同源**。原先这里另算了一套「进行中 N · 已完成 N」—— 完成态靠
      #    FINAL_STATUS_FALLBACK_RE 中文状态名正则猜，dist 用 MyModuleStatus
      #    #final_status?。生产库上两者打架：dist = Not started 115 / In progress 1，
      #    而 KPI 却算出「进行中 0 · 已完成 116」（final_status? 为真的 0 个），
      #    groups[].rate 又全是 0% —— 同一屏三处互相矛盾。
      #    现在 total 与 trend 全从 status_distribution 出，和条形图逐条可对拍
      #    （1 + 115 = 116），且不出现任何靠正则猜出来的「已完成 N」假数。
      def tasks_kpi
        rows = status_distribution
        total = rows.sum { |r| r[:num] }
        # 文案直接由**真实状态名 + 真数**拼（不翻译、不猜状态语义，
        # 与 dist 的条形标签逐条对得上）；最多取前 3 项，免得长条溢出卡片。
        trend = rows.first(TASK_TREND_LIMIT).map { |r| "#{r[:name]} #{r[:num]}" }.join(' · ')
        { label: '项目任务', value: total.to_s, trend: trend }
      end

      # ③ 项目总花费 = 消耗明细表按可读 project 聚合（口径同 REQ-RES-COST）
      def cost_kpi
        rows = cost_rows
        total = rows.sum { |r| r.amount.to_d }
        { label: '项目总花费', value: money(total), trend: cost_trend(rows, total) }
      end

      # ⚠ amount **带符号**（与 Ledger 同源：正=消耗、负=还回），
      #   直接 sum 就是净花费，取绝对值会把「还回冲减」变成「额外增加」。
      #   costable? 是明细表的验收口径：物资行恒计，服务行只有 settled 才计。
      def cost_rows
        return [] if readable_project_ids.empty?

        consume_record_model.where(project_id: readable_project_ids).select(&:costable?)
      rescue StandardError
        []
      end

      # 跨 addon 依赖：消耗明细表在 eln_ui 上。拿不到就显式空集（不炸 500）。
      def consume_record_model
        Scinote::ElnUi::ConsumeRecord
      rescue NameError
        nil
      end

      def cost_trend(rows, total)
        return '' if total.to_d.zero?

        parts = %w[material service].map do |kind|
          sum = rows.select { |r| r.kind == kind && r.amount.to_d.positive? }
                    .sum { |r| r.amount.to_d }
          label = kind == 'material' ? '材料' : '服务'
          next nil if sum.to_d.zero?

          "#{label} #{pct(sum, total)}%"
        end.compact
        return '' if parts.empty?

        parts.join(' · ')
      end

      def pct(part, total)
        return 0 unless total.to_d.nonzero?

        ((part.to_d * 100) / total.to_d).round
      end

      # 金额紧凑格式（¥12,400 / ¥12,340.50，整数不补 .00）
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
        mine = my_open_modules.first(room).map { |m| module_todo(m) }
        (approvals + mine).first(TODO_LIMIT)
      end

      # ① 待我审的资源申请：同队 + 非本人（审批口径与 ResourceApplicationWorkflow
      #    完全一致 —— 同源宽口径，不新建权限位）。
      def pending_approvals
        return [] if @team.nil? || @user.nil?

        model = resource_application_model
        return [] if model.nil?

        model.for_team(@team)
             .where(status: %w[submitted group_approved])
             .where.not(requestor_id: @user.id)
             .order('eln_ui_resource_applications.created_at' => :desc)
             .to_a
      rescue StandardError
        []
      end

      def resource_application_model
        Scinote::ElnUi::ResourceApplication
      rescue NameError
        nil
      end

      def approval_todo(app)
        {
          type: '资源申请',
          title: approval_title(app),
          # 资源申请单没有「截止日」列 → 显式留白，不编日期（OPEN-WORKBENCH-3）
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
        return [] if @user.nil?

        team_my_modules.joins(:user_assignments)
                       .where(user_assignments: { user_id: @user.id })
                       .distinct
                       .order(created_at: :desc)
                       .to_a
      rescue StandardError
        []
      end

      def module_todo(mod)
        status = mod.my_module_status&.name.to_s.presence || DASH
        {
          type: '任务',
          title: mod.name.to_s,
          due: due_label(mod),
          status: status,
          tone: final_status?(mod.my_module_status) ? 'primary' : 'warn'
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
      #
      # ★★ 唯一取数口径：`status_distribution` 一次算齐状态分组 + 完成态，
      #    **dist 与 kpis[项目任务].trend 复用同一个结果**，谁都不许再各算各的。
      #    这就是「构造性同源」—— 只有一条 SQL、一套 final_status? 谓词，
      #    页面上下两个数天然对拍得上（1 + 115 = 116）。
      def dist_block
        status_distribution.first(DIST_LIMIT).map do |row|
          { label: row[:name], num: row[:num], color: bar_color(row[:status]) }
        end
      rescue StandardError
        []
      end

      # 状态分布：按 my_module_status_id 分组计数 + MyModuleStatus#final_status?
      # 判完成态，按数量降序。**只对 dist / kpis 暴露**，groups 走 final_status_ids。
      # ⚠ 返回的内部行带 :status 对象（仅供 bar_color 取色用），不会进 JSON。
      def status_distribution
        @status_distribution ||= begin
          finals = final_status_ids
          team_my_modules.group(:my_module_status_id).count.map do |status_id, num|
            status = ::MyModuleStatus.unscoped.find_by(id: status_id)
            next nil if status.nil?

            { id: status_id, name: status.name.to_s, num: num,
              final: finals.include?(status_id), status: status }
          end.compact.sort_by { |row| -row[:num] }
        end
      end

      # 色值由**本服务**下发（组件内不硬编颜色）；原生浅色（如 Not started 的
      # #FFFFFF）白底上不可见 → 降级中性灰。
      def bar_color(status)
        return NEUTRAL_BAR_COLOR if status.nil?

        color = status.color.to_s.strip
        return NEUTRAL_BAR_COLOR if color.blank?

        begin
          return NEUTRAL_BAR_COLOR if status.light_color?
        rescue StandardError
          nil
        end

        color
      end

      def final_status_ids
        @final_status_ids ||= ::MyModuleStatus.unscoped.select { |s| final_status?(s) }.map(&:id)
      end

      def final_status?(status)
        return false if status.nil?
        return status.final_status? if status.respond_to?(:final_status?)

        FINAL_STATUS_FALLBACK_RE.match?(status.name.to_s)
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
        tone = if rate == DASH
                 nil
               else
                 pct(done, total) >= RATE_DONE_THRESHOLD ? 'done' : 'warn'
               end
        { name: group.name.to_s, leader: leader_label(group), rate: rate, tone: tone }
      end

      # ⚠ UserGroup 只有 (name/team_id/created_by_id/last_modified_by_id)，
      #   没有组长承载列 → 显式 '—'（OPEN-WORKBENCH-1，不猜不编）。
      def leader_label(group)
        return DASH unless group.respond_to?(:leader)

        group.leader.to_s.presence || DASH
      end

      # 组内组员「被指派任务」的完成态占比
      def member_task_stats(user_ids)
        return [0, 0] if user_ids.empty? || readable_project_ids.empty?

        assignments = ::UserAssignment.where(assignable_type: 'MyModule')
                                      .where(assignable_id: team_my_modules.select(:id))
                                      .where(user_id: user_ids)
        rows = assignments.to_a
        return [0, 0] if rows.empty?

        mods = team_my_modules.where(id: rows.map(&:assignable_id))
                              .includes(:my_module_status)
                              .index_by(&:id)
        finals = final_status_ids
        done = rows.count { |a| finals.include?(mods[a.assignable_id]&.my_module_status_id) }
        [rows.size, done]
      end

      # ------------------------------------------------------------
      # 6. entries（快捷入口：只发真源可达的宿主路由）
      # ------------------------------------------------------------
      # ⚠ 原型的「新建实验任务」「报表中心」宿主没有承载面 → **不输出**（显式留白）。
      #   每条 to 都从宿主路由表 real helper 取，取不到就不发这条（宁可少一条，
      #   也不发一个 404 的链接）。
      def entries_block
        [
          entry('项目管理', :eln_project_list_path),
          entry('资源中心', :eln_res_center_path)
        ].compact
      end

      def entry(label, helper_name)
        path = route_path(helper_name)
        return nil if path.blank?

        { label: label, to: path }
      end

      def route_path(helper_name)
        helpers = ::Rails.application.routes.url_helpers
        helpers.public_send(helper_name).to_s
      rescue StandardError
        ''
      end
    end
  end
end
