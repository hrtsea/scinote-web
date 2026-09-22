# frozen_string_literal: true

module Scinote
  module AiEln
    # 会话与交互的 REST 端点（规格 §4 ai_sessions / ai_interactions）
    class AiSessionsController < ApplicationController
      include HostModels

      before_action :ensure_enabled

      def show
        # TODO(issue-04): 渲染侧边抽屉面板所需会话数据
        head :not_implemented
      end

      def create
        # TODO(issue-04): 创建多态关联的 ai_session
        head :not_implemented
      end

      def destroy
        head :not_implemented
      end

      private

      def ensure_enabled
        head :forbidden unless Scinote::AiEln.enabled?
      end
    end
  end
end
