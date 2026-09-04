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

      # 对齐 AggregatorService#bottlenecks：7-14 / 14-<period> / <period>+ 天未更新，排除 completed?
      # <period> 来自设置页 default_period_days（默认 90），保证下钻与 widget 卡片计数一致。
      def apply_insights_stale_bucket(tasks, bucket)
        return tasks if bucket.blank?

        period = Scinote::ProjectInsights.default_period_days
        tasks = tasks.where.not(state: :completed)
        case bucket
        when 'seven'
          tasks.where('my_modules.updated_at <= ? AND my_modules.updated_at > ?', 7.days.ago, 14.days.ago)
        when 'fourteen'
          tasks.where('my_modules.updated_at <= ? AND my_modules.updated_at > ?', 14.days.ago, period.days.ago)
        when 'thirty_plus'
          tasks.where('my_modules.updated_at <= ?', period.days.ago)
        else
          tasks
        end
      end

      # 对齐 AggregatorService#due_dates 的五档互斥分桶（Overdue 独立成档，next_week 为兜底档）：
      #   overdue  = d < 今天
      #   today    = d == 今天
      #   tomorrow = d == 明天
      #   this_week= 明天 < d <= 本周末
      #   next_week= d > 本周末（且不等于明天）
      # 聚合侧是**日期级**比较（due_date.utc.to_date vs UTC 今天），故下钻一律用
      # **UTC 日界左闭右开区间** [d 00:00 UTC, d+1 00:00 UTC)，两侧时钟基准必须统一；
      # 否则跨日/跨时区会出现"卡片显示 N 个、下钻只有 N-1 个"的不一致。
      # （旧档名 due_today / due_this_week / upcoming 已于 2026-09-04 随 frame_014 复核废弃）
      def apply_insights_due_bucket(tasks, bucket)
        return tasks if bucket.blank?

        today = Time.current.utc.to_date
        # to_date 兜底：不同 Rails 版本下 Date#end_of_week 可能返回 Date 或 Time，统一成日期后再 +1 天
        week_end = today.end_of_week.to_date
        case bucket
        when 'overdue'
          tasks.where('my_modules.due_date < ?', utc_day_start(today))
        when 'today'
          between_utc_days(tasks, today, today + 1)
        when 'tomorrow'
          between_utc_days(tasks, today + 1, today + 2)
        when 'this_week'
          # 区间下界为 today+2（即"晚于明天"）；当本周末早于 today+2 时区间自然为空，与聚合一致。
          between_utc_days(tasks, today + 2, week_end + 1)
        when 'next_week'
          # 兜底档：晚于本周末，且跳过 tomorrow 档（周末早于 tomorrow 时以 tomorrow 的次日为下界）。
          lower = [utc_day_start(week_end + 1), utc_day_start(today + 2)].max
          tasks.where('my_modules.due_date >= ?', lower)
        else
          tasks
        end
      end

      # UTC 日界左闭右开区间：[from_date 00:00 UTC, to_date 00:00 UTC)
      def between_utc_days(tasks, from_date, to_date)
        tasks.where('my_modules.due_date >= ? AND my_modules.due_date < ?',
                    utc_day_start(from_date), utc_day_start(to_date))
      end

      def utc_day_start(date)
        Time.utc(date.year, date.month, date.day)
      end
    end
  end
end

Dashboard::CurrentTasksController.prepend(Scinote::ProjectInsights::CurrentTasksControllerDecorator)
