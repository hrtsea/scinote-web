# frozen_string_literal: true

require 'rails_helper'
require 'scinote/wechat_gateway'

module Scinote
  module WechatGateway
    RSpec.describe AiProcessor do
      def stub_ai(enabled:, endpoint: 'http://llm/v1')
        allow(Scinote::WechatGateway.configuration).to receive(:ai_enabled).and_return(enabled)
        allow(Scinote::WechatGateway.configuration).to receive(:ai_endpoint).and_return(endpoint)
        allow(Scinote::WechatGateway.configuration).to receive(:ai_model).and_return('m')
        allow(Scinote::WechatGateway.configuration).to receive(:ai_api_key).and_return(nil)
      end

      describe '.enabled?' do
        it '需 ai_enabled 且配置 endpoint' do
          stub_ai(enabled: true, endpoint: nil)
          expect(described_class.enabled?).to be false
          stub_ai(enabled: false)
          expect(described_class.enabled?).to be false
          stub_ai(enabled: true)
          expect(described_class.enabled?).to be true
        end
      end

      describe '.parse' do
        it 'JSON 字符串 -> StructuredRecord' do
          rec = described_class.parse(
            '{"experiment_title":"T","components":[{"name":"PP","amount":100,"unit":"g"}],' \
            '"results":[{"property":"冲击","value":23.5,"unit":"kJ/m²"}],"process_params":{"温度":200},"notes":"n"}'
          )
          expect(rec.experiment_title).to eq('T')
          expect(rec.components.first.name).to eq('PP')
          expect(rec.results.first.value).to eq(23.5)
          expect(rec.type).to eq('配方实验')
        end

        it '非法 JSON 返回 nil' do
          expect(described_class.parse('not json')).to be_nil
        end
      end

      describe '.format_body（GLP）' do
        it '保留原文并标需人工审核' do
          rec = described_class.parse(
            '{"experiment_title":"T","components":[{"name":"PP","amount":100,"unit":"g"}],' \
            '"results":[{"property":"冲击","value":23.5,"unit":"kJ/m²"}],"notes":"n"}'
          )
          body = described_class.format_body('原始消息内容', rec)
          expect(body).to include('【原始消息】')
          expect(body).to include('原始消息内容')
          expect(body).to include('【AI 辅助整理 · 需人工审核】')
          expect(body).to include('PP 100g')
          expect(body).to include('冲击 23.5kJ/m²')
        end
      end

      describe '.extract' do
        it '注入 llm 返回 JSON 时解析' do
          rec = described_class.extract('x', llm: ->(_t) { '{"experiment_title":"A"}' })
          expect(rec.experiment_title).to eq('A')
        end

        it 'llm 返回 StructuredRecord 时直接使用' do
          given = described_class::StructuredRecord.new(experiment_title: 'B')
          expect(described_class.extract('x', llm: ->(_t) { given })).to be(given)
        end

        it 'llm 抛错时降级 nil' do
          expect(described_class.extract('x', llm: ->(_t) { raise 'boom' })).to be_nil
        end

        it '未配置且无注入时返回 nil' do
          stub_ai(enabled: false, endpoint: nil)
          expect(described_class.extract('x')).to be_nil
        end
      end
    end
  end
end
