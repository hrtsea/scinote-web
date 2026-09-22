# frozen_string_literal: true

module Scinote
  module AiEln
    # LLM 适配层：本地私有化(Ollama) / OpenAI 兼容 API 可切换（规格 §7 / §3.2 安全）
    # 关闭 AI 时调用方应短路，不触达此层。
    class LlmAdapter
      class << self
        def complete(prompt:, model: Scinote::AiEln.configuration.model_name, max_token: Scinote::AiEln.configuration.max_token)
          case Scinote::AiEln.configuration.llm_backend
          when "ollama"
            complete_ollama(prompt, model, max_token)
          when "openai_compatible"
            complete_openai(prompt, model, max_token)
          else
            raise "unknown llm_backend: #{Scinote::AiEln.configuration.llm_backend}"
          end
        end

        private

        # 私有化优先：请求不离开内网，防配方泄露（规格 §6 / §3.2）
        def complete_ollama(prompt, model, max_token)
          uri = URI.join(Scinote::AiEln.configuration.api_endpoint, "chat/completions")
          http_post(uri, { model: model, messages: [{ role: "user", content: prompt }],
                           max_tokens: max_token })
        end

        def complete_openai(prompt, model, max_token)
          uri = URI.join(Scinote::AiEln.configuration.api_endpoint, "chat/completions")
          http_post(uri, { model: model, messages: [{ role: "user", content: prompt }],
                           max_tokens: max_token }, auth: Scinote::AiEln.configuration.api_key)
        end

        def http_post(uri, body, auth: nil)
          req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
          req["Authorization"] = "Bearer #{auth}" if auth
          req.body = body.to_json
          res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |h| h.request(req) }
          JSON.parse(res.body).dig("choices", 0, "message", "content").to_s
        end
      end
    end
  end
end
