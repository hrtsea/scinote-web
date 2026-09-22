# frozen_string_literal: true

module Scinote
  module AiEln
    # 合规审计日志导出（规格 AI-403）
    class AiAuditLogsController < ApplicationController
      before_action :ensure_enabled

      def index
        # TODO(issue-09): 管理员导出 ai_audit_logs
        head :not_implemented
      end

      private

      def ensure_enabled
        head :forbidden unless Scinote::AiEln.enabled?
      end
    end
  end
end
