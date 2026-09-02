# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module AiProtocols
    # 覆盖 Issue #3 AC4：llm_client 工厂在「配置齐全 / 单项缺失 / 完全缺失」三种情形下的
    # 配置优先级（AddonSetting.configuration > ENV > LlmClient::DEFAULT_MODEL）。
    # 既有 llm_client_spec 仅测 LlmClient 网络层，未断言该优先级，故此处补足。
    RSpec.describe 'Scinote::AiProtocols.llm_client (factory)' do
      let(:env_parser) { 'https://env-parser.test/v1' }
      let(:env_key) { 'env-secret' }
      let(:env_model) { 'env-model' }

      around do |example|
        original = {
          'AI_PROTOCOLS_PARSER' => ENV['AI_PROTOCOLS_PARSER'],
          'AI_PROTOCOLS_API_KEY' => ENV['AI_PROTOCOLS_API_KEY'],
          'AI_PROTOCOLS_MODEL' => ENV['AI_PROTOCOLS_MODEL']
        }
        ENV['AI_PROTOCOLS_PARSER'] = env_parser
        ENV['AI_PROTOCOLS_API_KEY'] = env_key
        ENV['AI_PROTOCOLS_MODEL'] = env_model
        example.run
      ensure
        original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end

      before { AddonSetting.update_for('ai_protocols', enabled: true, configuration: {}) }
      after  { AddonSetting.for('ai_protocols').update!(configuration: {}) }

      it 'prefers AddonSetting.configuration when fully configured' do
        AddonSetting.update_for('ai_protocols', enabled: true,
          configuration: { parser_url: 'https://cfg.test/v1', api_key: 'cfg-key', model: 'cfg-model' })
        client = Scinote::AiProtocols.llm_client
        expect(client.base_url).to eq('https://cfg.test/v1')
        expect(client.api_key).to eq('cfg-key')
        expect(client.model).to eq('cfg-model')
      end

      it 'falls back to ENV for a single missing field (parser_url set, api_key/model unset)' do
        AddonSetting.update_for('ai_protocols', enabled: true,
          configuration: { parser_url: 'https://cfg.test/v1' })
        client = Scinote::AiProtocols.llm_client
        expect(client.base_url).to eq('https://cfg.test/v1')
        expect(client.api_key).to eq(env_key)
        expect(client.model).to eq(env_model)
      end

      it 'falls back entirely to ENV when no configuration is set' do
        AddonSetting.update_for('ai_protocols', enabled: true, configuration: {})
        client = Scinote::AiProtocols.llm_client
        expect(client.base_url).to eq(env_parser)
        expect(client.api_key).to eq(env_key)
        expect(client.model).to eq(env_model)
      end

      it 'uses LlmClient::DEFAULT_MODEL when model is neither configured nor in ENV' do
        ENV.delete('AI_PROTOCOLS_MODEL')
        AddonSetting.update_for('ai_protocols', enabled: true,
          configuration: { parser_url: 'https://cfg.test/v1', api_key: 'cfg-key' })
        client = Scinote::AiProtocols.llm_client
        expect(client.model).to eq(Scinote::AiProtocols::LlmClient::DEFAULT_MODEL)
      end

      it 'raises when neither config nor ENV supplies a base_url (no regression vs pre-migration)' do
        ENV.delete('AI_PROTOCOLS_PARSER')
        AddonSetting.update_for('ai_protocols', enabled: true, configuration: {})
        expect { Scinote::AiProtocols.llm_client }
          .to raise_error(Scinote::AiProtocols::LlmClient::ConfigurationError)
      end
    end
  end
end
