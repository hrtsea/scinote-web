# frozen_string_literal: true

require 'net/http'
require 'json'

module Scinote
  module AiProtocols
    # OpenAI-compatible LLM client used to turn free text / extracted PDF text
    # into structured SciNote protocol JSON.
    #
    # Configuration precedence (per instance): explicit arg > ENV.
    #   AI_PROTOCOLS_PARSER -> base URL of the OpenAI-compatible endpoint
    #                         (e.g. https://api.openai.com/v1 or an Azure endpoint).
    #                         Reuses the host's existing feature-flag ENV.
    #   AI_PROTOCOLS_API_KEY -> bearer token (optional for some self-hosted endpoints).
    #   AI_PROTOCOLS_MODEL   -> model name (default: gpt-4o-mini).
    #
    # The client is intentionally thin and mockable: the network call lives in
    # the private #post method so specs can stub it without hitting the wire.
    class LlmClient
      class ConfigurationError < StandardError; end

      class ApiError < StandardError; end

      # Wraps transient server/network failures that are safe to retry.
      class RetryableApiError < ApiError; end

      DEFAULT_MODEL = 'gpt-4o-mini'
      # Transient failures worth retrying: server errors (5xx) and network hiccups.
      MAX_RETRIES = 2
      RETRYABLE = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError].freeze

      def self.for(provider = :openai)
        case provider
        when :openai then new
        else raise ArgumentError, "Unsupported LLM provider: #{provider}"
        end
      end

      def initialize(base_url: nil, api_key: nil, model: nil)
        @base_url = base_url || ENV.fetch('AI_PROTOCOLS_PARSER', nil)
        @api_key = api_key || ENV.fetch('AI_PROTOCOLS_API_KEY', nil)
        @model = model || ENV.fetch('AI_PROTOCOLS_MODEL', DEFAULT_MODEL)
        validate!
      end

      # Calls the chat completion endpoint and returns the model's JSON output
      # already parsed into a Ruby Hash. `schema` is an OpenAI json_schema hash;
      # `schema_name` names it (letters/numbers/underscores only).
      def chat_with_schema(system_prompt:, user_prompt:, schema:, schema_name: 'protocol')
        raw = post(completions_url, build_body(system_prompt, user_prompt, schema, schema_name))
        parse_content(raw)
      end

      attr_reader :base_url, :api_key, :model

      private

      def validate!
        return if base_url.present?

        raise ConfigurationError, 'AI_PROTOCOLS_PARSER (LLM base URL) is not set'
      end

      def completions_url
        "#{base_url.chomp('/')}/chat/completions"
      end

      def build_body(system_prompt, user_prompt, schema, schema_name)
        {
          model:,
          messages: [
            { role: 'system', content: system_prompt },
            { role: 'user', content: user_prompt }
          ],
          response_format: {
            type: 'json_schema',
            json_schema: { name: schema_name.to_s, strict: true, schema: }
          }
        }
      end

      def post(url, body)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 120

        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req['Authorization'] = "Bearer #{api_key}" if api_key.present?
        req.body = body.to_json

        retries = 0
        begin
          res = http.request(req)
          return res.body if res.is_a?(Net::HTTPSuccess)

          # 4xx are client errors and must not be retried; 5xx is retried below.
          error_class = res.is_a?(Net::HTTPClientError) ? ApiError : RetryableApiError
          raise error_class, "LLM API returned #{res.code}: #{res.body}"
        rescue *RETRYABLE, RetryableApiError
          retries += 1
          retry if retries <= MAX_RETRIES
          raise
        end

        res.body
      end

      def parse_content(raw)
        data = JSON.parse(raw)
        content = data.dig('choices', 0, 'message', 'content')
        raise ApiError, 'LLM response missing choices[0].message.content' if content.blank?

        JSON.parse(content)
      end
    end
  end
end
