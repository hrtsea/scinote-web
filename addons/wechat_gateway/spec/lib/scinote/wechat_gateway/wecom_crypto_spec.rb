# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'
require 'base64'
require 'digest'

module Scinote
  module WechatGateway
    RSpec.describe WecomCrypto do
      let(:encoding_aes_key) do
        key = SecureRandom.random_bytes(32)
        Base64.strict_encode64(key)[0, 43]
      end
      let(:receive_id) { 'ww1234567890abcdef' }

      it 'roundtrips ascii and unicode' do
        ['hello wecom', '实验记录 🚀 中文'].each do |msg|
          enc = described_class.encrypt(msg, receive_id, encoding_aes_key)
          expect(described_class.decrypt(enc, encoding_aes_key, receive_id)).to eq(msg)
        end
      end

      it 'validates signature and detects tamper' do
        token = 'mytoken'
        ts = '1700000000'
        nonce = 'abc'
        encrypt = Base64.strict_encode64('x')
        sig = Digest::SHA1.hexdigest([token, ts, nonce, encrypt].sort.join)
        expect(described_class.verify_signature(token, ts, nonce, encrypt, sig)).to be true
        expect(described_class.verify_signature(token, ts, nonce, encrypt, 'deadbeef')).to be false
      end

      it 'raises on receive_id mismatch' do
        msg = 'hi'
        enc = described_class.encrypt(msg, receive_id, encoding_aes_key)
        expect { described_class.decrypt(enc, encoding_aes_key, 'wrong-corpid') }.to raise_error(RuntimeError)
      end

      it 'decrypt_callback roundtrips' do
        msg = '群消息内容'
        enc = described_class.encrypt(msg, receive_id, encoding_aes_key)
        sig = Digest::SHA1.hexdigest(['tok', '123', 'n', enc].sort.join)
        xml = "<xml><ToUserName><![CDATA[to]]></ToUserName><Encrypt><![CDATA[#{enc}]></Encrypt></xml>"
        described_class.config = { token: 'tok', encoding_aes_key: encoding_aes_key, receive_id: receive_id }
        params = { timestamp: '123', nonce: 'n', msg_signature: sig }
        expect(described_class.decrypt_callback(xml, params)).to eq(msg)
      end
    end
  end
end
