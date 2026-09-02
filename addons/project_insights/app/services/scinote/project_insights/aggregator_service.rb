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
      def initialize(user, team)
        @user = user
        @team = team
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
      def workload
        rows = scoped_tasks
               .joins(:user_my_modules)
               .group('user_my_modules.user_id', :my_module_status_id)
               .count

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

      # 按截止日期四档现算（UTC，对齐核心 overdue 作用域）。
      # 无 due_date 的任务不计入任何档。
      def due_dates
        result = { overdue: 0, due_today: 0, due_this_week: 0, upcoming: 0 }
        scoped_tasks.where.not(due_date: nil).pluck(:due_date).each do |due_date|
          if due_date.utc < Time.current.utc
            result[:overdue] += 1
          elsif due_date.to_date == Date.current
            result[:due_today] += 1
          elsif due_date.to_date <= Date.current.end_of_week
            result[:due_this_week] += 1
          else
            result[:upcoming] += 1
          end
        end
        result
      end

      private

      def scoped_tasks
        MyModule.active
                .readable_by_user(@user, @team)
                .joins(experiment: :project)
                .where(experiments: { archived: false }, projects: { archived: false })
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
    end
  end
end
