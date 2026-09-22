# frozen_string_literal: true

module Scinote
  module AiEln
    # 配方性质：实测值(measured_*) + 目标值(target_*/comparator)
    # my_module_id 指向宿主实验任务实例：设计目标为 NULL，实测值挂具体批次(S3)
    class FormulationProperty < ActiveRecord::Base
      self.table_name = "ai_eln_formulation_properties"

      belongs_to :formulation,
                 class_name: "Scinote::AiEln::Formulation",
                 inverse_of: :formulation_properties

      validates :name, presence: true
      validate :measured_or_target_present

      private

      def measured_or_target_present
        return if measured_value.present? || target_value.present?

        errors.add(:base, "measured_value 或 target_value 至少其一必填")
      end
    end
  end
end
