# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module AiProtocols
    RSpec.describe LlmClient do
      let(:base_url) { 'https://api.openai.com/v1' }

      before do
        ENV['AI_PROTOCOLS_PARSER'] = base_url
        ENV['AI_PROTOCOLS_API_KEY'] = 'secret'
        ENV['AI_PROTOCOLS_MODEL'] = 'gpt-4o-mini'
      end

      after do
        ENV.delete('AI_PROTOCOLS_PARSER')
        ENV.delete('AI_PROTOCOLS_API_KEY')
        ENV.delete('AI_PROTOCOLS_MODEL')
      end

      describe '#initialize' do
        it 'reads base_url from ENV when not passed explicitly' do
          expect(described_class.new.base_url).to eq(base_url)
        end

        it 'raises ConfigurationError when base_url is missing' do
          ENV.delete('AI_PROTOCOLS_PARSER')
          expect { described_class.new }.to raise_error(described_class::ConfigurationError)
        end
      end

      describe '#chat_with_schema' do
        it 'parses the JSON content returned by the API' do
          body = { choices: [{ message: { content: '{"name":"x"}' } }] }.to_json
          stub_request(:post, "#{base_url}/chat/completions")
            .to_return(status: 200, body:, headers: { 'Content-Type' => 'application/json' })

          result = described_class.new.chat_with_schema(
            system_prompt: 's', user_prompt: 'u', schema: { type: 'object' }, schema_name: 'protocol'
          )
          expect(result).to eq('name' => 'x')
        end

        it 'retries transient 5xx errors and returns on eventual success' do
          body = { choices: [{ message: { content: '{"name":"x"}' } }] }.to_json
          stub_request(:post, "#{base_url}/chat/completions")
            .to_return(status: 503, body: 'unavailable').then
            .to_return(status: 200, body:)

          result = described_class.new.chat_with_schema(
            system_prompt: 's', user_prompt: 'u', schema: { type: 'object' }, schema_name: 'protocol'
          )
          expect(result).to eq('name' => 'x')
          expect(WebMock).to have_requested(:post, "#{base_url}/chat/completions").times(2)
        end

        it 'does not retry 4xx client errors' do
          stub_request(:post, "#{base_url}/chat/completions")
            .to_return(status: 400, body: 'bad request')

          expect do
            described_class.new.chat_with_schema(
              system_prompt: 's', user_prompt: 'u', schema: { type: 'object' }, schema_name: 'protocol'
            )
          end.to raise_error(described_class::ApiError)
          expect(WebMock).to have_requested(:post, "#{base_url}/chat/completions").times(1)
        end
      end
    end
  end
end
