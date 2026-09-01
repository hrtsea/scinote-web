# frozen_string_literal: true

# 下钻联动（P8）：在 enabled? 时扩展 Dashboard::CurrentTasksController 的过滤，
# 使各 widget 能精确下钻到 current_tasks。仅追加 where 条件，基础链路
# （MyModule.active.readable_by_user...）沿用 core；新参数边界与 AggregatorService
# 的分桶完全一致（避免下钻数量与 widget 卡片不符）。
module Scinote
  module ProjectInsights
    module CurrentTasksControllerDecorator
      def task_filters
        # 在 core 白名单基础上追加下钻参数。
        params.permit(
          :project_id, :experiment_id, :mode, :sort, :query, :page,
          :assigned_user_id, :stale_bucket, :due_bucket, statuses: []
        )
      end

      def load_tasks
        tasks = super
        return tasks unless Scinote::ProjectInsights.enabled?

        f = task_filters
        tasks = apply_insights_assigned_user(tasks, f[:assigned_user_id])
        tasks = apply_insights_stale_bucket(tasks, f[:stale_bucket])
        apply_insights_due_bucket(tasks, f[:due_bucket])
      end

      private

      def apply_insights_assigned_user(tasks, user_id)
        return tasks if user_id.blank?

        tasks.joins(:user_my_modules).where(user_my_modules: { user_id: user_id })
      end

      # 对齐 AggregatorService#bottlenecks：7-14 / 14-30 / 30+ 天未更新，排除 completed?
      def apply_insights_stale_bucket(tasks, bucket)
        return tasks if bucket.blank?

        tasks = tasks.where.not(state: :completed)
        case bucket
        when 'seven'
          tasks.where('my_modules.updated_at <= ? AND my_modules.updated_at > ?', 7.days.ago, 14.days.ago)
        when 'fourteen'
          tasks.where('my_modules.updated_at <= ? AND my_modules.updated_at > ?', 14.days.ago, 30.days.ago)
        when 'thirty_plus'
          tasks.where('my_modules.updated_at <= ?', 30.days.ago)
        else
          tasks
        end
      end

      # 对齐 AggregatorService#due_dates 的互斥分桶（先判 overdue，today 已过的任务归入 overdue）：
      # overdue = utc<now；due_today = [now, 今日结束]；due_this_week = (今日结束, 本周末]；upcoming = >本周末
      def apply_insights_due_bucket(tasks, bucket)
        return tasks if bucket.blank?

        case bucket
        when 'overdue'
          tasks.where('my_modules.due_date < ?', Time.current.utc)
        when 'due_today'
          tasks.where('my_modules.due_date >= ? AND my_modules.due_date <= ?', Time.current.utc, Time.current.end_of_day)
        when 'due_this_week'
          tasks.where('my_modules.due_date > ? AND my_modules.due_date <= ?', Time.current.end_of_day, Date.current.end_of_week)
        when 'upcoming'
          tasks.where('my_modules.due_date > ?', Date.current.end_of_week)
        else
          tasks
        end
      end
    end
  end
end

Dashboard::CurrentTasksController.prepend(Scinote::ProjectInsights::CurrentTasksControllerDecorator)
