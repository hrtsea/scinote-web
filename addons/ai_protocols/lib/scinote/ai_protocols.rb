# frozen_string_literal: true

require 'scinote/ai_protocols/engine'
require 'scinote/ai_protocols/llm_client'
require 'scinote/ai_protocols/version'

module Scinote
  module AiProtocols
    # 构建运行期 LLM 客户端。配置优先级：
    #   显式参数 > AddonSetting.configuration（设置页填写）> ENV（AI_PROTOCOLS_*）
    # 这样设置页填写的 parser_url/api_key/model 实际生效；缺失某项时回退到既有 ENV，
    # 保证未配置实例行为与迁移前一致（见 ADR-013）。
    def self.llm_client
      config = AddonSetting.for('ai_protocols').configuration || {}
      base_url = config['parser_url'].presence || ENV['AI_PROTOCOLS_PARSER']
      api_key = config['api_key'].presence || ENV['AI_PROTOCOLS_API_KEY']
      model = config['model'].presence || ENV['AI_PROTOCOLS_MODEL'] || LlmClient::DEFAULT_MODEL
      LlmClient.new(base_url: base_url, api_key: api_key, model: model)
    end

    # 声明本 addon 在"设置 → Addons"页所需的配置项，由设置页据 type 动态渲染表单，
    # 并类型化存储到 addon_settings.configuration。
    # 运行期已由 self.llm_client 优先消费此配置（回退 ENV），见 ADR-013。
    def self.config_schema
      [
        {
          key: 'parser_url',
          type: 'string',
          label: 'scinote_ai_protocols.settings.config.parser_url',
          help: 'scinote_ai_protocols.settings.config.parser_url_help',
          placeholder: 'https://api.openai.com/v1'
        },
        {
          key: 'api_key',
          type: 'secret',
          label: 'scinote_ai_protocols.settings.config.api_key',
          help: 'scinote_ai_protocols.settings.config.api_key_help'
        },
        {
          key: 'model',
          type: 'select',
          label: 'scinote_ai_protocols.settings.config.model',
          default: 'gpt-4o-mini',
          options: [
            { value: 'gpt-4o-mini', label: 'scinote_ai_protocols.settings.config.model.gpt4o_mini' },
            { value: 'gpt-4o',      label: 'scinote_ai_protocols.settings.config.model.gpt4o' },
            { value: 'gpt-4-turbo', label: 'scinote_ai_protocols.settings.config.model.gpt4_turbo' }
          ]
        }
      ].freeze
    end

    # 设置页卡片简介（参照 Label printers 的标题+描述风格）。
    def self.description
      'scinote_ai_protocols.settings.description'
    end

    # 配置子页的详细说明。
    def self.detailed_help
      'scinote_ai_protocols.settings.detailed_help'
    end
  end
end
