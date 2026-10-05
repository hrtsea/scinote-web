# frozen_string_literal: true

# ⚠️ DEPRECATED（2026-09-24，D-persist=B「全盘替换」）
# 审计导出改由 ActiveAgent 的 actionagent 面板承担（AI-403 合规导出复用其 telemetry）。
# 本控制器保留为路由占位，避免离线断链；实例 boot 后随三张表一并移除。

module Scinote
  module AiEln
    # 合规审计日志导出（规格 AI-403）【已 DEPRECATED，改走 actionagent 面板】
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
