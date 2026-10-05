# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'
require 'base64'
require 'digest'

module Scinote
  module WechatGateway
    # 内存存储桩（仅 Inbound 用到 find_binding）
    class FakeStore
      def initialize
        @b = {}
      end

      def find_binding(wechat_id, platform)
        @b["#{wechat_id}:#{platform}"]
      end

      def create_binding(uid, wid, plat)
        @b["#{wid}:#{plat}"] = uid
      end
    end

    def self.make_aeskey
      key = SecureRandom.random_bytes(32)
      Base64.strict_encode64(key)[0, 43]
    end

    # 加密 inner XML -> 外层 <xml><Encrypt> + 计算 msg_signature
    def self.wrap_wecom(corpid, aeskey, token, inner_xml)
      enc = WecomCrypto.encrypt(inner_xml, corpid, aeskey)
      outer = "<xml><ToUserName><![CDATA[#{corpid}]]></ToUserName>" \
              "<Encrypt><![CDATA[#{enc}]></Encrypt></xml>"
      sig = Digest::SHA1.hexdigest([token, '1700000000', 'n0nce', enc].sort.join)
      [outer, { timestamp: '1700000000', nonce: 'n0nce', msg_signature: sig }]
    end

    def self.text_inner(corpid, content)
      "<xml><ToUserName><![CDATA[#{corpid}]]></ToUserName>" \
      "<FromUserName><![CDATA[u_wx_123]]></FromUserName>" \
      "<CreateTime>1700000000</CreateTime>" \
      "<MsgType><![CDATA[text]]></MsgType>" \
      "<Content><![CDATA[#{content}]]></Content><MsgId>99</MsgId></xml>"
    end

    RSpec.describe WecomMessageParser do
      let(:corpid) { 'ww1234567890abcdef' }

      it 'parses text' do
        m = described_class.parse(text_inner(corpid, '实验记录 🚀'))
        expect(m.user_id).to eq('u_wx_123')
        expect(m.text).to eq('实验记录 🚀')
        expect(m.type).to eq(:text)
        expect(m.platform).to eq(:wecom)
        expect(m.timestamp).to eq(1_700_000_000)
      end

      it 'parses image with media' do
        xml = text_inner(corpid, 'x').sub(
          '<MsgType><![CDATA[text]]></MsgType><Content><![CDATA[x]]></Content>',
          '<MsgType><![CDATA[image]]></MsgType><MediaId><![CDATA[mid_1]]></MediaId>' \
          '<PicUrl><![CDATA[https://cdn/p]]></PicUrl>'
        )
        m = described_class.parse(xml)
        expect(m.type).to eq(:image)
        expect(m.media.size).to eq(1)
        expect(m.media[0][:kind]).to eq(:image)
        expect(m.media[0][:media_id]).to eq('mid_1')
        expect(m.media[0][:url]).to eq('https://cdn/p')
      end

      it 'parses group ChatId and @ mentions' do
        xml = text_inner(corpid, "\u0001@zhangsan\u0001 做实验").sub(
          '<MsgId>99</MsgId>',
          '<MsgId>99</MsgId><ChatId><![CDATA[wr_group_1]]></ChatId>'
        )
        m = described_class.parse(xml)
        expect(m.chat_id).to eq('wr_group_1')
        expect(m.mentions).to eq(['zhangsan'])
        expect(m.text).to eq(' 做实验')
      end

      it 'parses event text' do
        xml = text_inner(corpid, 'x').sub(
          '<MsgType><![CDATA[text]]></MsgType><Content><![CDATA[x]]></Content>',
          '<MsgType><![CDATA[event]]></MsgType><Event><![CDATA[subscribe]]></Event>' \
          '<EventKey><![CDATA[ek1]]></EventKey>'
        )
        m = described_class.parse(xml)
        expect(m.type).to eq(:event)
        expect(m.text).to eq('subscribe:ek1')
      end
    end

    RSpec.describe Inbound do
      let(:corpid) { 'ww1234567890abcdef' }
      let(:aeskey) { Scinote.make_aeskey }
      let(:token) { 'mytoken' }
      let(:store) { FakeStore.new }
      let(:inner) { Scinote.text_inner(corpid, '实验记录 🚀') }

      before do
        WecomCrypto.config = { token: token, encoding_aes_key: aeskey, receive_id: corpid }
        Inbound.store = store
        Inbound.intake_handler = ->(uid, msg) { "intake:#{uid}:#{msg.text}" }
      end

      after do
        Inbound.store = nil
        Inbound.intake_handler = nil
      end

      it 'receive bound dispatches to intake' do
        store.create_binding(42, 'u_wx_123', :wecom)
        outer, params = Scinote.wrap_wecom(corpid, aeskey, token, inner)
        res = described_class.receive(:wecom, outer, params)
        expect(res[:bound]).to be true
        expect(res[:user_id]).to eq(42)
        expect(res[:message].text).to eq('实验记录 🚀')
        expect(res[:message].platform).to eq(:wecom)
        expect(res[:intake]).to eq('intake:42:实验记录 🚀')
      end

      it 'receive unbound returns guidance' do
        outer, params = Scinote.wrap_wecom(corpid, aeskey, token, inner)
        res = described_class.receive(:wecom, outer, params)
        expect(res[:bound]).to be false
        expect(res[:user_id]).to be_nil
        expect(res[:guidance]).to be_truthy
      end

      it 'dispatch contract unchanged (bound -> user_id, unbound -> nil)' do
        store.create_binding(42, 'u_wx_123', :wecom)
        outer, params = Scinote.wrap_wecom(corpid, aeskey, token, inner)
        msg = described_class.parse(:wecom, outer, params)
        expect(described_class.dispatch(:wecom, msg)).to eq(42)

        described_class.store = FakeStore.new
        msg2 = described_class.parse(:wecom, outer, params)
        expect(described_class.dispatch(:wecom, msg2)).to be_nil
      end
    end
  end
end
