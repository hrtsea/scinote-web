# frozen_string_literal: true

module Scinote
  module AiEln
    # 每一轮对话 / 调用记录（规格 §4 ai_interactions + ADR-0004 状态机）
    # 状态机：queued(0) → streaming(1) → completed(2) / failed(3) / cancelled(4)
    # 审计写入由适配层在流结束后调用，不在 model 回调即时镜像（ADR-0002/0004）
    class AiInteraction < ActiveRecord::Base
      self.table_name = "ai_eln_ai_interactions"

      belongs_to :ai_session, class_name: "Scinote::AiEln::AiSession", foreign_key: :ai_session_id

      enum :status, { queued: 0, streaming: 1, completed: 2, failed: 3, cancelled: 4 }
    end
  end
end
