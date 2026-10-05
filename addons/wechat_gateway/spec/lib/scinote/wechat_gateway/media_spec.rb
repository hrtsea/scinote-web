# frozen_string_literal: true

require 'rails_helper'
require 'scinote/wechat_gateway'

module Scinote
  module WechatGateway
    RSpec.describe Media do
      after { described_class.http_get = nil }

      it '有 url 时直接 GET' do
        described_class.http_get = ->(url) { "bytes:#{url}" }
        expect(described_class.fetch({ url: 'http://cdn/p' })).to eq('bytes:http://cdn/p')
      end

      it 'full_url 优先于 url' do
        described_class.http_get = ->(url) { url }
        expect(described_class.fetch({ url: 'a', full_url: 'b' })).to eq('b')
      end

      it '仅 media_id（无 url/aes_key）返回 nil' do
        expect(described_class.fetch({ kind: :image, media_id: 'mid' })).to be_nil
      end

      it '带 aes_key 时走 IlinkBridge.download_media' do
        expect(IlinkBridge).to receive(:download_media)
          .with({ aes_key: 'k', full_url: 'u' }, http_get: anything)
          .and_return('img')
        expect(described_class.fetch({ aes_key: 'k', full_url: 'u' })).to eq('img')
      end

      it '取流异常时降级为 nil' do
        described_class.http_get = ->(_url) { raise 'boom' }
        expect(described_class.fetch({ url: 'http://cdn/p' })).to be_nil
      end
    end
  end
end
