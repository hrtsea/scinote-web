# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'
require 'openssl'
require 'base64'

module Scinote
  module WechatGateway
    # 内存存储桩（仅 Inbound 用到 find_binding）
    class FakeStore
      def initialize
        @bindings = {}
      end

      def find_binding(wechat_id, platform)
        @bindings["#{wechat_id}:#{platform}"]
      end

      def create_binding(user_id, wechat_id, platform)
        @bindings["#{wechat_id}:#{platform}"] = user_id
      end
    end

    def self.aes128_ecb_encrypt(plain, key)
      pad = 16 - (plain.bytesize % 16)
      pad = 16 if pad.zero?
      padded = plain.encode('UTF-8') + pad.chr * pad
      c = OpenSSL::Cipher.new('AES-128-ECB')
      c.encrypt
      c.key = key
      c.padding = 0
      c.update(padded) + c.final
    end

    RSpec.describe IlinkCrypto do
      it 'aes128_ecb roundtrip' do
        key = SecureRandom.random_bytes(16)
        plain = '实验记录 🚀 中文'
        ct = Scinote.aes128_ecb_encrypt(plain, key)
        expect(described_class.aes128_ecb_decrypt(ct, key).force_encoding('UTF-8')).to eq(plain)
      end

      it 'decrypts media via base64 key' do
        key = SecureRandom.random_bytes(16)
        aeskey = Base64.strict_encode64(key)
        plain = 'media-bytes-123'
        ct = Scinote.aes128_ecb_encrypt(plain, key)
        expect(described_class.decrypt_media(ct, aeskey).force_encoding('UTF-8')).to eq(plain)
      end

      it 'decodes aes key to 16 bytes' do
        key = SecureRandom.random_bytes(16)
        expect(described_class.decode_aes_key(Base64.strict_encode64(key))).to eq(key)
      end
    end

    RSpec.describe IlinkMessageParser do
      def text_and_image_raw
        {
          'message_type' => 1,
          'from_user_id' => 'wxuser123',
          'create_time_ms' => 1_700_000_000_000,
          'item_list' => [
            { 'type' => 'text', 'text_item' => { 'text' => '实验记录A' } },
            { 'type' => 'image', 'image_item' => { 'aeskey' => 'KEY1', 'url' => 'https://cdn/x' } }
          ]
        }
      end

      it 'parses text and image' do
        msg = described_class.parse(text_and_image_raw)
        expect(msg.user_id).to eq('wxuser123')
        expect(msg.text).to eq('实验记录A')
        expect(msg.type).to eq(:image)
        expect(msg.media.size).to eq(1)
        expect(msg.media[0][:kind]).to eq(:image)
        expect(msg.media[0][:aes_key]).to eq('KEY1')
        expect(msg.platform).to eq(:ilink)
      end

      it 'parses voice with transcript' do
        raw = { 'message_type' => 1, 'from_user_id' => 'u',
                'item_list' => [{ 'voice_item' => { 'text' => '转写文本', 'aeskey' => 'K', 'url' => 'u' } }] }
        msg = described_class.parse(raw)
        expect(msg.type).to eq(:voice)
        expect(msg.media[0][:text]).to eq('转写文本')
      end

      it 'parses file with name' do
        raw = { 'message_type' => 1, 'from_user_id' => 'u',
                'item_list' => [{ 'file_item' => { 'file_name' => 'note.pdf', 'len' => '10', 'aeskey' => 'K' } }] }
        msg = described_class.parse(raw)
        expect(msg.type).to eq(:file)
        expect(msg.media[0][:file_name]).to eq('note.pdf')
      end

      it 'group field env changes user_id' do
        ENV['ILINK_GROUP_FIELD'] = 'room_id'
        raw = text_and_image_raw.merge('room_id' => 'R1')
        msg = described_class.parse(raw)
        expect(msg.user_id).to eq('g.R1.wxuser123')
      ensure
        ENV.delete('ILINK_GROUP_FIELD')
      end
    end

    RSpec.describe IlinkBridge do
      class Spy
        attr_reader :calls

        def initialize
          @calls = []
        end

        def dispatch(platform, msg)
          @calls << [platform, msg]
        end
      end

      it 'skips bot and dispatches' do
        spy = Spy.new
        queue = [
          { 'message_type' => 1, 'from_user_id' => 'u1', 'item_list' => [{ 'text_item' => { 'text' => 'hi' } }] },
          { 'message_type' => 2, 'from_user_id' => 'u1', 'item_list' => [] }, # BOT 自回包
          nil
        ]
        described_class.run(-> { queue.shift }, handler: spy)
        expect(spy.calls.size).to eq(1)
        expect(spy.calls[0][0]).to eq(:ilink)
        expect(spy.calls[0][1].user_id).to eq('u1')
      end

      it 'Inbound returns nil when unbound' do
        Inbound.store = FakeStore.new
        raw = { 'message_type' => 1, 'from_user_id' => 'nobody', 'item_list' => [{ 'text_item' => { 'text' => 'x' } }] }
        msg = IlinkMessageParser.parse(raw)
        expect(Inbound.dispatch(:ilink, msg)).to be_nil
      ensure
        Inbound.store = nil
      end
    end
  end
end
