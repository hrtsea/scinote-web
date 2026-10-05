# frozen_string_literal: true

# ⚠️ DEPRECATED（2026-09-24，D-persist=B「全盘替换」）
# 审计日志（AI-403 合规导出）改由 ActiveAgent 的 actionagent 面板 telemetry 承担。
# 表 ai_eln_ai_audit_logs 保留（已迁移建表），但不再有新的写入逻辑；新代码走 actionagent 面板。
# 移除见后续迁移（实例 boot 后统一 drop_table）。

module Scinote
  module AiEln
    # 独立审计日志表（ADR-0002，不写原生 Activity）
    # 字段：user_id / created_at / prompt / response / model_name / token_usage / status / 多态关联
    # 规格 §4 ai_audit_logs（AI-403 合规导出）
    class AiAuditLog < ActiveRecord::Base
      self.table_name = "ai_eln_ai_audit_logs"

      belongs_to :user, class_name: -> { Scinote::AiEln.configuration.user_class }, optional: true
      belongs_to :ai_audit_loggable, polymorphic: true, optional: true
    end
  end
end
