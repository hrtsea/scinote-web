# frozen_string_literal: true

require 'rails_helper'
require 'scinote/wechat_gateway'

module Scinote
  module WechatGateway
    RSpec.describe Vision do
      after do
        described_class.fetcher = nil
        described_class.http_post = nil
      end

      def stub_endpoint(value)
        allow(Scinote::WechatGateway.configuration).to receive(:vision_endpoint).and_return(value)
      end

      it '未配置端点时禁用且 describe 返回 nil' do
        stub_endpoint(nil)
        expect(described_class.enabled?).to be false
        expect(described_class.describe({ kind: :image })).to be_nil
      end

      it '启用时经 fetcher + http_post 取识别文本' do
        stub_endpoint('http://sidecar/ocr')
        described_class.fetcher = ->(_d) { 'bytes' }
        described_class.http_post = ->(_url, _bytes, _d) { { 'text' => '菌落呈圆形' }.to_json }
        expect(described_class.describe({ kind: :image })).to eq('菌落呈圆形')
      end

      it 'fetcher 返回 nil 时降级为 nil' do
        stub_endpoint('http://sidecar/ocr')
        described_class.fetcher = ->(_d) { nil }
        expect(described_class.describe({ kind: :image })).to be_nil
      end

      it 'http_post 抛错时降级为 nil（不阻塞录入）' do
        stub_endpoint('http://sidecar/ocr')
        described_class.fetcher = ->(_d) { 'bytes' }
        described_class.http_post = ->(*) { raise 'boom' }
        expect(described_class.describe({ kind: :image })).to be_nil
      end

      it 'parse_text 兼容 text/description 字段与纯文本响应' do
        expect(described_class.parse_text('{"text":"A"}')).to eq('A')
        expect(described_class.parse_text('{"description":"B"}')).to eq('B')
        expect(described_class.parse_text('plain')).to eq('plain')
        expect(described_class.parse_text('{"foo":"bar"}')).to be_nil
      end
    end
  end
end
