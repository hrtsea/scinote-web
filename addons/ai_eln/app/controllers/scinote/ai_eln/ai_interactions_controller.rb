# frozen_string_literal: true

module Scinote
  module AiEln
    # 单轮对话创建端点（规格 §4 ai_interactions，状态机 queued→streaming→...）
    class AiInteractionsController < ApplicationController
      before_action :ensure_enabled

      def create
        # TODO(issue-03): 入队 Delayed Job，经 Solid Cable 流式推送
        head :not_implemented
      end

      private

      def ensure_enabled
        head :forbidden unless Scinote::AiEln.enabled?
      end
    end
  end
end
