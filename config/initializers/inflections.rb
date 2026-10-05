# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# activeagent gem 在其 railtie 中全局注册了 acronym "AI"，
# 导致 Zeitwerk 把所有 ai_* 路径段变形为 AI*（如 Scinote::AIProtocols），
# 与本项目 addons 的 Scinote::AiProtocols / Scinote::AiEln 命名冲突。
# 此处用 autoloaders 的 inflector 覆盖恢复 Ai 前缀。
# 注意：新增 ai_ 开头的文件/目录时需在此登记。
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect(
    "ai_eln" => "AiEln",
    "ai_protocols" => "AiProtocols",
    "ai_actions_controller" => "AiActionsController",
    "ai_audit_log" => "AiAuditLog",
    "ai_audit_logs_controller" => "AiAuditLogsController",
    "ai_embedding" => "AiEmbedding",
    "ai_interaction" => "AiInteraction",
    "ai_interactions_controller" => "AiInteractionsController",
    "ai_processor" => "AiProcessor",
    "ai_protocol_create_button" => "AiProtocolCreateButton",
    "ai_session" => "AiSession",
    "ai_sessions_controller" => "AiSessionsController",
    "ai_summarize_job" => "AiSummarizeJob"
  )
end
