# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'
require 'base64'
require 'digest'
require 'scinote/wechat_gateway'

module Scinote
  module WechatGateway
    RSpec.describe 'Inbound /bind wiring' do
      let(:corpid) { 'ww1234567890abcdef' }
      let(:aeskey) { Base64.strict_encode64(SecureRandom.random_bytes(32))[0, 43] }
      let(:token) { 'mytoken' }

      # 完整内存存储：在 FakeStore 基础上补绑定码方法，供 /bind 链路使用
      class FullStore
        def initialize
          @b = {}
          @codes = {}
        end

        def find_binding(wid, plat)
          @b["#{wid}:#{plat}"]
        end

        def create_binding(uid, wid, plat)
          @b["#{wid}:#{plat}"] = uid
        end

        def save_code(code, uid, exp)
          @codes[code] = { user_id: uid, expires_at: exp, used: false }
        end

        def fetch_code(code)
          @codes[code]
        end

        def mark_code_used(code)
          @codes[code] && @codes[code][:used] = true
        end
      end

      let(:store) { FullStore.new }

      def wrap(content)
        enc = WecomCrypto.encrypt(content, corpid, aeskey)
        outer = "<xml><ToUserName><![CDATA[#{corpid}]]></ToUserName>" \
                "<Encrypt><![CDATA[#{enc}]></Encrypt></xml>"
        sig = Digest::SHA1.hexdigest([token, '1700000000', 'n0nce', enc].sort.join)
        [outer, { timestamp: '1700000000', nonce: 'n0nce', msg_signature: sig }]
      end

      def inner(content)
        "<xml><ToUserName><![CDATA[#{corpid}]]></ToUserName>" \
          "<FromUserName><![CDATA[u_wx_123]]></FromUserName>" \
          "<CreateTime>1700000000</CreateTime>" \
          "<MsgType><![CDATA[text]]></MsgType>" \
          "<Content><![CDATA[#{content}]]></Content><MsgId>99</MsgId></xml>"
      end

      before do
        WecomCrypto.config = { token: token, encoding_aes_key: aeskey, receive_id: corpid }
        Inbound.store = store
        Inbound.intake_handler = ->(uid, _msg) { "intake:#{uid}" }
      end

      after do
        Inbound.store = nil
        Inbound.intake_handler = nil
      end

      it '未绑定用户 /bind 有效码 -> 绑定成功并落库' do
        code = BindCode.new(store).generate(42)
        outer, params = wrap(inner("/bind #{code}"))
        res = Inbound.receive(:wecom, outer, params)
        expect(res[:bind]).to be true
        expect(res[:ok]).to be true
        expect(res[:reply]).to match(/绑定成功/)
        expect(store.find_binding('u_wx_123', :wecom)).to eq(42)
      end

      it '已绑定用户 /bind -> 提示已绑定，不改写' do
        store.create_binding(42, 'u_wx_123', :wecom)
        code = BindCode.new(store).generate(7)
        outer, params = wrap(inner("/bind #{code}"))
        res = Inbound.receive(:wecom, outer, params)
        expect(res[:bind]).to be true
        expect(res[:ok]).to be false
        expect(res[:reply]).to match(/已经绑定过/)
        expect(store.find_binding('u_wx_123', :wecom)).to eq(42)
      end

      it '无效/过期码 -> 失败' do
        outer, params = wrap(inner('/bind ZZZZZZZZ'))
        res = Inbound.receive(:wecom, outer, params)
        expect(res[:bind]).to be true
        expect(res[:ok]).to be false
        expect(res[:reply]).to match(/无效或已过期/)
      end

      it '非 /bind 消息仍走原 unbound 分支' do
        outer, params = wrap(inner('随便记点东西'))
        res = Inbound.receive(:wecom, outer, params)
        expect(res[:bind]).to be_nil
        expect(res[:bound]).to be false
        expect(res[:guidance]).to be_truthy
      end
    end
  end
end
