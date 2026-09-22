# frozen_string_literal: true

module Scinote
  module AiEln
    # 配方（组成定义，一等实体；ADR-0006）
    # 组成见 FormulationComponent；性质(实测/目标)见 FormulationProperty
    class Formulation < ActiveRecord::Base
      self.table_name = "ai_eln_formulations"

      belongs_to :team, class_name: "Team"
      belongs_to :created_by, class_name: -> { Scinote::AiEln.configuration.user_class }

      has_many :formulation_components,
               class_name: "Scinote::AiEln::FormulationComponent",
               inverse_of: :formulation, dependent: :destroy
      has_many :formulation_properties,
               class_name: "Scinote::AiEln::FormulationProperty",
               inverse_of: :formulation, dependent: :destroy
      has_many :repository_rows, through: :formulation_components, class_name: "RepositoryRow"

      validates :name, presence: true
    end
  end
end
