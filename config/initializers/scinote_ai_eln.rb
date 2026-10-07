# frozen_string_literal: true

# SciNote AI 助手 addon（ai_eln）宿主配置。
#
# 契约依据：docs/development/addons-host-contract.md
#   - 路由：由 addon engine 的 'scinote_ai_eln.routes' initializer 自挂载，
#     宿主 config/routes.rb 保持零 mount —— 勿在此 mount（README 的 mount 指引已作废）。
#   - 权限：ai_eln 未新增 Canaid 权限谓词，而是复用宿主既有谓词（经下方 can_*_proc 注入），
#     故本 addon 不需要 app/permissions 目录（契约 §5.1.3）。
#
# 注：早期接入片段曾调用 `Canaid.register_permissions_under(:ai)` —— 该 API 在 Canaid 1.0.4
# 中并不存在（已核实），照抄会致 boot 期 NoMethodError，故此处不予采用。

# ⚠️ ai_eln addon 已于 2026-10-07 从 Gemfile 停用。
#本文件随之保留但整段条件化：gem 不在 Gemfile 时 `Scinote::AiEln` 常量不存在，
# 裸调 configure 会让 Rails 启动即NameError → 全站 500。
# 恢复 addon：把 Gemfile 那行取消注释即可，本文件的 if defined? 同样兼容（真机在时正常执行）。
if defined?(Scinote::AiEln)
  Scinote::AiEln.configure do |config|
    # 全局开关：默认关；置 AI_ELN_ENABLED=true 后 addon 路由与端点才生效
    config.enable       = ENV.fetch('AI_ELN_ENABLED', 'false') == 'true'

    # 推理后端（LlmAdapter 语义；ActiveAgent 侧统一走 ruby_llm，见 config/active_agent.yml）
    config.llm_backend  = ENV.fetch('AI_ELN_LLM_BACKEND', 'ollama')
    config.api_endpoint = ENV.fetch('AI_ELN_API_ENDPOINT', 'http://127.0.0.1:11434/v1')
    config.model_name   = ENV.fetch('AI_ELN_MODEL_NAME', 'qwen2.5-14b-instruct')
    config.api_key      = ENV['AI_ELN_API_KEY']
    config.max_token    = ENV.fetch('AI_ELN_MAX_TOKEN', '4096').to_i
    config.ocr_backend  = ENV.fetch('AI_ELN_OCR_BACKEND', 'local')
    config.llm_retry    = ENV.fetch('AI_ELN_LLM_RETRY', 'false') == 'true'
  end

  # 宿主能力注入：转发宿主 Canaid 真实谓词（零侵入，不硬编码宿主常量）。
  # 谓词已逐一核实存在于 app/permissions/ 下：
  #   user.can_read_experiment?              ← app/permissions/experiment.rb:21
  #   user.can_read_protocol_in_repository?  ← app/permissions/protocol.rb:15
  #   user.can_read_protocol_in_module?      ← app/permissions/protocol.rb:103
  #   user.can_read_asset?                   ← app/permissions/asset.rb:4
  Scinote::AiEln.configure do |config|
    config.can_read_experiment_proc = lambda { |user, experiment|
      user.can_read_experiment?(experiment)
    }

    # 协议存在两种语境（仓库协议 / 任务内协议），二者取或以覆盖两种情况。
    config.can_read_protocol_proc = lambda { |user, protocol|
      (user.respond_to?(:can_read_protocol_in_repository?) &&
        user.can_read_protocol_in_repository?(protocol)) ||
        (user.respond_to?(:can_read_protocol_in_module?) &&
          user.can_read_protocol_in_module?(protocol))
    }

    config.can_read_asset_proc = lambda { |user, asset|
      user.can_read_asset?(asset)
    }

    # 当前宿主未注册 create_experiment 谓词（experiment.rb 无该 can），默认拒绝，
    # 避免误放行；待宿主补谓词后再接线。
    config.can_create_experiment_proc = ->(_user, _experiment) { false }
  end
end
