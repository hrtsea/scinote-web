# frozen_string_literal: true

# 项目洞察 addon 的核心模块
module Scinote
  module ProjectInsights
    # 灰度门控：是否启用本 addon 的 dashboard 组件
    # 对齐 docs/FEATURE_FLAGS.md 的全局 ENV 开关约定
    def self.enabled?
      ENV['PROJECT_INSIGHTS_ENABLED'] == 'true'
    end

    # 追加到 Extends::DEFAULT_DASHBOARD_CONFIGURATION 的 widget 配置
    # 字段必须与 app/views/dashboards/show.html.erb 读取的 schema 一致：
    #   partial, visible, size, position
    WIDGETS = [
      { partial: 'dashboards/insights_status',      visible: true, size: 'medium-widget', position: 4 },
      { partial: 'dashboards/insights_workload',    visible: true, size: 'medium-widget', position: 5 },
      { partial: 'dashboards/insights_bottlenecks', visible: true, size: 'small-widget',  position: 6 },
      { partial: 'dashboards/insights_due_dates',   visible: true, size: 'medium-widget', position: 7 }
    ].freeze

    # 注册 widget 到 dashboard 配置；抽出方法便于测试与去重
    # 由 engine 的 config.to_prepare 调用
    def self.register_widgets!
      return unless enabled?

      registered = Extends::DEFAULT_DASHBOARD_CONFIGURATION.pluck(:partial)
      WIDGETS.each do |widget|
        Extends::DEFAULT_DASHBOARD_CONFIGURATION << widget unless registered.include?(widget[:partial])
      end
    end
  end
end
