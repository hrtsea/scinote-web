# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module AiProtocols
    # Issue #3：ai_protocols 在运行期实际消费设置页配置（parser_url/api_key/model），
    # 缺失某项时回退到既有 ENV（AI_PROTOCOLS_*），保证未配置实例行为不变。
    RSpec.describe Scinote::AiProtocols do
      let(:full_config) do
        { 'parser_url' => 'https://config.example.com/v1', 'api_key' => 'cfg-key', 'model' => 'gpt-4o' }
      end

      around do |example|
        ENV.delete('AI_PROTOCOLS_PARSER')
        ENV.delete('AI_PROTOCOLS_API_KEY')
        ENV.delete('AI_PROTOCOLS_MODEL')
        example.run
        ENV.delete('AI_PROTOCOLS_PARSER')
        ENV.delete('AI_PROTOCOLS_API_KEY')
        ENV.delete('AI_PROTOCOLS_MODEL')
      end

      before do
        AddonSetting.for('ai_protocols').update!(configuration: {})
      end

      it '从 AddonSetting 配置构建 LLM 客户端（三项齐全）' do
        AddonSetting.for('ai_protocols').update!(configuration: full_config)
        client = described_class.llm_client
        expect(client.base_url).to eq('https://config.example.com/v1')
        expect(client.api_key).to eq('cfg-key')
        expect(client.model).to eq('gpt-4o')
      end

      it '配置缺失某项时回退到 ENV（行为不变）' do
        ENV['AI_PROTOCOLS_PARSER'] = 'https://env.example.com/v1'
        ENV['AI_PROTOCOLS_API_KEY'] = 'env-key'
        ENV['AI_PROTOCOLS_MODEL'] = 'gpt-4o-mini'
        # 仅配置 parser_url，api_key / model 应回退 ENV
        AddonSetting.for('ai_protocols').update!(configuration: { 'parser_url' => 'https://config.example.com/v1' })

        client = described_class.llm_client
        expect(client.base_url).to eq('https://config.example.com/v1') # 来自配置
        expect(client.api_key).to eq('env-key')                        # 来自 ENV 回退
        expect(client.model).to eq('gpt-4o-mini')                     # 来自 ENV 回退
      end

      it '完全无配置时整体回退 ENV' do
        ENV['AI_PROTOCOLS_PARSER'] = 'https://env.example.com/v1'
        ENV['AI_PROTOCOLS_MODEL'] = 'gpt-4o'
        client = described_class.llm_client
        expect(client.base_url).to eq('https://env.example.com/v1')
        expect(client.model).to eq('gpt-4o')
      end
    end
  end
end
