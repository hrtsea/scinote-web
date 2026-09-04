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

    # 注：P1 的 dashboard widget 注册已撤销。addon 改为独立 /insights 页面
    # （app/views/insights/index.html.erb）承载 4 个 widget，避免在 dashboard
    # 与独立页之间重复展示；widget partial 仍位于 app/views/dashboards/。
  end
end
