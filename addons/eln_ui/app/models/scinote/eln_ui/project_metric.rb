# frozen_string_literal: true

# 项目指标（eln_ui_project_metrics）—— 原生 projects 没有指标承载面。
# 外壳照 design_variable.rb 抄：裹 module、table_name 前缀、belongs_to 带 ::。
module Scinote
  module ElnUi
    class ProjectMetric < ActiveRecord::Base
      self.table_name = 'eln_ui_project_metrics'

      belongs_to :project, class_name: '::Project', inverse_of: false

      scope :ordered, -> { order(:position, :id) }
    end
  end
end
