# frozen_string_literal: true

Scinote::AiEln::Engine.routes.draw do
  # 全局开关：enable=false 时完全不加载 AI 路由（规格 §7 / issue-01）
  return unless Scinote::AiEln.enabled?

  # 侧边抽屉面板挂载点（规格 §3 UI 界面）
  resources :ai_sessions, only: %i[show create destroy] do
    resources :ai_interactions, only: %i[create], controller: "ai_interactions"
  end

  # 单功能端点（规格 §2 各 AI-xxx）
  post "experiments/:experiment_id/summarize",   to: "ai_actions#summarize",        as: :exp_summarize
  post "experiments/:experiment_id/root_cause",  to: "ai_actions#root_cause",       as: :exp_root_cause
  post "protocols/:protocol_id/parse_recipe",    to: "ai_actions#parse_recipe",     as: :proto_parse_recipe
  post "attachments/:asset_id/parse",            to: "ai_actions#parse_attachment", as: :attach_parse
  post "semantic_search",                        to: "ai_actions#semantic_search",  as: :semantic_search

  # 合规审计导出（规格 AI-403）
  get "audit_logs", to: "ai_audit_logs#index", as: :audit_logs
end
