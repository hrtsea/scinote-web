# frozen_string_literal: true

module Scinote
  module ElnUi
    # 实验级 DOE「设计变量」（DV）—— 纯二开表，原生无对应物。
    #
    # 区间存成 range_min / range_max / unit 三列（而不是一个 range 文本列），
    # 前端渲染的是数据；categorical 类变量（如牌号）没有 min/max，由 payload 按
    # var_type 走「无区间」分支显示，不硬凑字符串。
    class DesignVariable < ActiveRecord::Base
      self.table_name = 'eln_ui_design_variables'

      belongs_to :experiment, class_name: '::Experiment', inverse_of: false

      # var_type 取值域与原型 expDesignVars.type 对齐，payload 直接透传。
      TYPES = %w[float integer categorical].freeze

      validates :var_type, inclusion: { in: TYPES }

      scope :ordered, -> { order(:position, :id) }
    end
  end
end
