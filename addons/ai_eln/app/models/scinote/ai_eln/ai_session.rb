# frozen_string_literal: true

# ⚠️ DEPRECATED（2026-09-24，D-persist=B「全盘替换」）
# 会话能力已由 ActiveAgent 的 actionagent 面板（solid_agent）统一承载。
# 表 ai_eln_ai_sessions 保留（已迁移建表），但不再有新的写入逻辑；新代码走 actionagent 可观测性。
# 移除见后续迁移（实例 boot 后统一 drop_table）。

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
