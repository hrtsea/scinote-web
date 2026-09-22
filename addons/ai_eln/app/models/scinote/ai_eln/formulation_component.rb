# frozen_string_literal: true

module Scinote
  module AiEln
    # 配方组成项：成分(repository_row) + 投料量(amount/unit)
    # 复用宿主 RepositoryRow 物料主数据；单位归一化在读取/训练抽取层处理（S2），schema 不强制
    class FormulationComponent < ActiveRecord::Base
      self.table_name = "ai_eln_formulation_components"

      belongs_to :formulation,
                 class_name: "Scinote::AiEln::Formulation",
                 inverse_of: :formulation_components
      belongs_to :repository_row, class_name: "RepositoryRow"

      validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
      validates :unit, presence: true
      validates :repository_row_id, uniqueness: { scope: :formulation_id }
    end
  end
end
