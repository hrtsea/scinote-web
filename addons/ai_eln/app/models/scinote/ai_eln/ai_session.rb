# frozen_string_literal: true

module Scinote
  module AiEln
    # 会话主表，多态关联宿主实体（ADR-0001）
    # 关联范围：Experiment / StepText / ResultText / FormResponse / Table（无 Recipe/Protocol）
    # 规格 §4 ai_sessions
    class AiSession < ActiveRecord::Base
      self.table_name = "ai_eln_ai_sessions"

      belongs_to :user, class_name: -> { Scinote::AiEln.configuration.user_class }
      belongs_to :ai_sessionable, polymorphic: true, optional: false
      has_many :ai_interactions, class_name: "Scinote::AiEln::AiInteraction",
               foreign_key: :ai_session_id, dependent: :destroy
    end
  end
end
