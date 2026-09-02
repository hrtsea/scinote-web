# frozen_string_literal: true

# 项目洞察 addon 的核心模块
module Scinote
  module ProjectInsights
    # 门控：本 addon 是否在实例级别启用。
    # 接入 AddonSetting 契约：设置页的启用开关写入 addon_settings 表，
    # 未写入设置行时按"已挂载即默认启用"（opt-out），与 AddonSetting.enabled? 一致。
    def self.enabled?
      AddonSetting.enabled?('project_insights')
    end

    # 声明本 addon 在"设置 → Addons"页所需的配置项（暴露给管理员填写）。
    def self.config_schema
      [
        {
          key: 'default_period_days',
          type: 'integer',
          label: 'project_insights.settings.config.default_period_days',
          help: 'project_insights.settings.config.default_period_days_help',
          placeholder: '90',
          default: 90
        }
      ].freeze
    end

    # 设置页卡片简介（参照 Label printers 的标题+描述风格）。
    def self.description
      'project_insights.settings.description'
    end

    # 配置子页的详细说明。
    def self.detailed_help
      'project_insights.settings.detailed_help'
    end

    # 读取本 addon 的某项实例级配置（来自 addon_settings.configuration）。
    def self.config_value(key)
      AddonSetting.for('project_insights').config_value(key)
    end

    # 瓶颈检测的"陈旧阈值"：未更新超过该天数的任务计入 bottlenecks 的 thirty_plus 桶。
    # 读取设置页配置 default_period_days，缺失时回退默认 90 天（见 ADR-013）。
    DEFAULT_PERIOD_DAYS = 90
    def self.default_period_days
      (config_value('default_period_days') || DEFAULT_PERIOD_DAYS).to_i
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
