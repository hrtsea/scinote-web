# frozen_string_literal: true

module Scinote
  module ProjectInsights
    # 团队内可读项目的聚合服务（Issue P2）
    #
    # 范围与权限链路对齐 dashboard/current_tasks_controller#load_tasks：
    #   MyModule.active
    #     .readable_by_user(user, team)
    #     .joins(experiment: :project)
    #     .where(projects: { archived: false }, experiments: { archived: false })
    #
    # 全部为 Ruby / SQL 侧聚合，避免 N+1；大团队可对
    # updated_at / due_date / my_module_status_id 建覆盖索引。
    class AggregatorService
      def initialize(user, team, project = nil)
        @user = user
        @team = team
        @project = project
      end

      # 按 my_module_status 聚合任务数，回带团队可见状态流
      # （当前 team 自有的 in_team 流 ∪ global 流）的全部状态名/色；
      # 无任务的状态计数记为 0（结构契约：各 widget 渲染前即知完整状态集合）。
      def status_overview
        counts = scoped_tasks.group(:my_module_status_id).count
        visible_statuses.map do |status|
          {
            id: status.id,
            name: status.name,
            color: status.color,
            count: counts.fetch(status.id, 0)
          }
        end
      end

      # 按 指派用户(designated_users) × 状态 聚合任务数。
      # 每个 (user, status) 组合返回一行，便于前端堆叠柱图分组。
      # member_ids 非空时仅统计所选成员（D 可交互成员多选）。
      def workload(member_ids: nil)
        relation = scoped_tasks.joins(:user_my_modules)
        relation = relation.where(user_my_modules: { user_id: member_ids }) if member_ids.present?
        rows = relation.group('user_my_modules.user_id', :my_module_status_id).count

        user_index = User.where(id: rows.keys.map(&:first).uniq).index_by(&:id)
        status_index = MyModuleStatus.where(id: rows.keys.map(&:second).uniq).index_by(&:id)

        rows.map do |(user_id, status_id), count|
          user = user_index[user_id]
          status = status_index[status_id]
          {
            user_id: user_id,
            user_name: user.full_name,
            status_id: status_id,
            status_name: status.name,
            status_color: status.color,
            count: count
          }
        end
      end

      # 按 updated_at 分桶（已排除 completed? 任务）：
      # 7 天内 / 14 天内 / 超过 default_period_days 天未更新（陈旧阈值来自设置页，默认 90）。
      def bottlenecks(period: Scinote::ProjectInsights.default_period_days)
        tasks = scoped_tasks.where.not(state: :completed)
        {
          seven: tasks.where('my_modules.updated_at <= ? AND my_modules.updated_at > ?', 7.days.ago, 14.days.ago).count,
          fourteen: tasks.where('my_modules.updated_at <= ? AND my_modules.updated_at > ?', 14.days.ago, period.days.ago).count,
          thirty_plus: tasks.where('my_modules.updated_at <= ?', period.days.ago).count
        }
      end

      # 按截止日期五档现算（UTC，对齐核心 overdue 作用域）。
      # 与官方 UI（frame_014）一致：Overdue / Today / Tomorrow / This week / Next week。
      # ⚠️ 官方只有 5 个 tab 且无「More weeks」，故比 Next week 更晚的截止
      # 统一归入最末档 next_week（兜底档），不单独统计。
      # 档位判定集中在 #due_date_bucket，与 #tasks_for 共用同一谓词，保证
      # 「卡片计数 == 下钻列表条数」（避免卡片 N 个 / 列表 N-1 个）。
      def due_dates
        result = { overdue: 0, today: 0, tomorrow: 0, this_week: 0, next_week: 0 }
        scoped_tasks.where.not(due_date: nil).find_each do |task|
          result[due_date_bucket(task.due_date)] += 1
        end
        result
      end

      # 按档返回任务列表（待补 G / Bottlenecks 分段选择器）：
      # 复用 #bucket_of 谓词，与对应聚合计数保持同名同边界。
      def tasks_for(kind, bucket)
        case kind
        when :due_dates then tasks_in_bucket(:due_dates, bucket)
        when :bottlenecks then tasks_in_bucket(:bottlenecks, bucket)
        else []
        end
      end

      private

      def scoped_tasks
        scope = MyModule.active
                        .readable_by_user(@user, @team)
                        .joins(experiment: :project)
                        .where(experiments: { archived: false }, projects: { archived: false })
        scope = scope.where(projects: { id: @project.id }) if @project
        scope
      end

      # 当前 team 自有的 in_team 流 ∪ 全局 global 流，再取其 my_module_statuses。
      # ⚠️ 2026-09-01 实证校正：状态流不可从 current_team.my_module_status_flows 取
      # （Team 模型无此关联），须直接查 MyModuleStatusFlow。
      def visible_statuses
        flows = MyModuleStatusFlow
                .where(team_id: @team.id, visibility: :in_team)
                .or(MyModuleStatusFlow.global)
        MyModuleStatus.where(my_module_status_flow: flows).order(:my_module_status_flow_id, :id)
      end

      # 取某 kind 下某个桶的任务集合（已按该 kind 的范围预过滤）。
      def tasks_in_bucket(kind, bucket)
        scope = scoped_tasks
        scope = scope.where.not(due_date: nil) if kind == :due_dates
        scope = scope.where.not(state: :completed) if kind == :bottlenecks
        scope.includes(:my_module_status, :designated_users).flat_map do |task|
          bucket_of(task, kind) == bucket ? [task_payload(task, kind)] : []
        end
      end

      # 任务归属桶（与聚合计数使用同一判定，保证一致）。
      def bucket_of(task, kind)
        case kind
        when :due_dates then due_date_bucket(task.due_date)
        when :bottlenecks then bottleneck_bucket(task.updated_at)
        end
      end

      # 截止日期五档（UTC，与 due_dates 计数共用）：Overdue / Today / Tomorrow /
      # This week / Next week（比 Next week 更晚的截止归入 next_week 兜底）。
      def due_date_bucket(due_date)
        d = due_date.utc.to_date
        today = Time.current.utc.to_date
        end_of_week = today.end_of_week.to_date
        if d < today then :overdue
        elsif d == today then :today
        elsif d == today + 1 then :tomorrow
        elsif d <= end_of_week then :this_week
        else
          :next_week
        end
      end

      # 陈旧分桶（UTC）：>7 天未更新不入任何桶；7–14 天=seven；14–<period> 天=fourteen；
      # <=period 天=thirty_plus（period 来自设置页默认 90）。
      def bottleneck_bucket(updated_at)
        return nil if updated_at > 7.days.ago
        return :seven if updated_at > 14.days.ago

        period = Scinote::ProjectInsights.default_period_days
        return :fourteen if updated_at > period.days.ago

        :thirty_plus
      end

      # 档内任务列表的单条负载（名称 + 状态色 + 日期 + 指派人）。
      def task_payload(task, kind)
        date_field = kind == :due_dates ? :due_date : :updated_at
        {
          id: task.id,
          name: task.name,
          status_name: task.my_module_status&.name,
          status_color: task.my_module_status&.color,
          date: task.public_send(date_field)&.iso8601,
          assigned_user_names: task.designated_users.map(&:full_name)
        }
      end
    end
  end
end
