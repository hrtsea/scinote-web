# frozen_string_literal: true

# 项目花费登记行（eln_ui_project_cost_items）—— REQ-RES-COST 全自动口径落地前的
# 人工登记面。一行 = 一个类别的汇总行（与原型 mock.projectCost.rows 同形状）；
# 总额/占比由 payload 现算，不落表。
module Scinote
  module ElnUi
    class ProjectCostItem < ActiveRecord::Base
      self.table_name = 'eln_ui_project_cost_items'

      belongs_to :project, class_name: '::Project', inverse_of: false

      scope :ordered, -> { order(:position, :id) }
    end
  end
end
