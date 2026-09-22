# frozen_string_literal: true

# 宿主接入片段（零侵入）：复制此文件内容到 SciNote 宿主的
# config/initializers/scinote_ai_eln.rb，按需调整配置与权限转发。
#
# 引擎经官方 addon 发现机制（addons_helper#list_all_addons 识别
# `Scinote::AiEln` 命名空间前缀）自动被枚举，但权限需此处的 Canaid 注册。

# 1) 全局开关与 LLM / OCR 后端配置
Scinote::AiEln.configure do |config|
  config.enable      = ENV.fetch("AI_ELN_ENABLED", "false") == "true"
  config.llm_backend = ENV.fetch("AI_ELN_LLM_BACKEND", "ollama")
  config.api_endpoint = ENV.fetch("AI_ELN_API_ENDPOINT", "http://127.0.0.1:11434/v1")
  config.model_name  = ENV.fetch("AI_ELN_MODEL_NAME", "qwen2.5-14b-instruct")
  config.api_key     = ENV["AI_ELN_API_KEY"]
  config.max_token   = ENV.fetch("AI_ELN_MAX_TOKEN", "4096").to_i
  config.ocr_backend = ENV.fetch("AI_ELN_OCR_BACKEND", "local")
  config.llm_retry   = ENV.fetch("AI_ELN_LLM_RETRY", "false") == "true"
end

# 2) Canaid 权限注册（issue-01：ai:use 挂到 owner / normal_user / technician）
Canaid.register_permissions_under(:ai) do
  root 'ai' do
    can :use, 'ai:use'
  end

  role :owner do
    can :use
  end

  role :normal_user do
    can :use
  end

  role :technician do
    can :use
  end
end

# 3) 宿主能力注入（create-engine HARD-GATE #3：不硬编码宿主常量，复用宿主鉴权）
Scinote::AiEln.configure do |config|
  config.can_read_experiment_proc   = ->(user, experiment) { user.can_read_experiment?(experiment) }
  config.can_create_experiment_proc = ->(user, experiment) { user.can_create_experiment?(experiment) }
end
