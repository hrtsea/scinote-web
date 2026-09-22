# frozen_string_literal: true

module Scinote
  module AiEln
    class Configuration
      # ── 宿主模型契约：全部字符串引用，绝不硬编码 ::Experiment / ::Protocol ──
      attr_accessor :experiment_class, :protocol_class, :report_class,
                    :user_class, :recipe_class

      # ── 全局开关与 LLM 后端（规格 §7）──
      attr_accessor :enable, :llm_backend, :api_endpoint, :model_name, :api_key, :max_token

      # ── OCR 后端双轨（规格 AI-102）：本地模型 / 公有 API，同 LLM 开关机制 ──
      attr_accessor :ocr_backend

      # ── 流式重试（ADR-0004）：默认关，开启时指数退避限 3 次 ──
      attr_accessor :llm_retry

      # ── 宿主能力注入点（由 SciNote 在 initializer 中提供实现）──
      attr_accessor :can_read_experiment_proc, :can_create_experiment_proc

      def initialize
        @experiment_class = "Experiment"
        @protocol_class   = "Protocol"
        @report_class     = "Report"
        @recipe_class     = "Recipe"
        @user_class       = "User"

        @enable       = false
        @llm_backend  = "ollama"            # ollama / openai_compatible
        @api_endpoint = "http://127.0.0.1:11434/v1"
        @model_name   = "qwen2.5-14b-instruct"
        @api_key      = nil
        @max_token    = 4096
        @ocr_backend  = "local"             # local / public_api
        @llm_retry    = false

        # 权限默认拒绝，宿主必须注入真实实现（零侵入、权限复用 §1.2-2）
        @can_read_experiment_proc     = ->(_user, _exp) { false }
        @can_create_experiment_proc   = ->(_user, _exp) { false }
      end
    end
  end
end
