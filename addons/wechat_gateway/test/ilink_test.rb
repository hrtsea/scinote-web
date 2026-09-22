require 'minitest/autorun'
require 'securerandom'
require 'openssl'
require 'base64'
require_relative '../lib/scinote/wechat_gateway/message'
require_relative '../lib/scinote/wechat_gateway/ilink_crypto'
require_relative '../lib/scinote/wechat_gateway/ilink_message_parser'
require_relative '../lib/scinote/wechat_gateway/ilink_bridge'
require_relative '../lib/scinote/wechat_gateway/inbound'

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

def aes128_ecb_encrypt(plain, key)
  pad = 16 - (plain.bytesize % 16)
  pad = 16 if pad.zero?
  padded = plain.encode('UTF-8') + pad.chr * pad
  c = OpenSSL::Cipher.new('AES-128-ECB')
  c.encrypt
  c.key = key
  c.padding = 0
  c.update(padded) + c.final
end

class IlinkCryptoTest < Minitest::Test
  def test_aes128_ecb_roundtrip
    key = SecureRandom.random_bytes(16)
    plain = '实验记录 🚀 中文'
    ct = aes128_ecb_encrypt(plain, key)
    # 媒体解密返回二进制；文本场景需按 UTF-8 解读
    assert_equal plain, Scinote::WechatGateway::IlinkCrypto.aes128_ecb_decrypt(ct, key).force_encoding('UTF-8')
  end

  def test_decrypt_media_via_base64_key
    key = SecureRandom.random_bytes(16)
    aeskey = Base64.strict_encode64(key)
    plain = 'media-bytes-123'
    ct = aes128_ecb_encrypt(plain, key)
    assert_equal plain, Scinote::WechatGateway::IlinkCrypto.decrypt_media(ct, aeskey).force_encoding('UTF-8')
  end

  def test_decode_aes_key_is_16_bytes
    key = SecureRandom.random_bytes(16)
    assert_equal key, Scinote::WechatGateway::IlinkCrypto.decode_aes_key(Base64.strict_encode64(key))
  end
end

class IlinkMessageParserTest < Minitest::Test
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

  def test_text_and_image
    msg = Scinote::WechatGateway::IlinkMessageParser.parse(text_and_image_raw)
    assert_equal 'wxuser123', msg.user_id
    assert_equal '实验记录A', msg.text
    assert_equal :image, msg.type
    assert_equal 1, msg.media.size
    assert_equal :image, msg.media[0][:kind]
    assert_equal 'KEY1', msg.media[0][:aes_key]
    assert_equal :ilink, msg.platform
  end

  def test_voice_with_transcript
    raw = { 'message_type' => 1, 'from_user_id' => 'u',
            'item_list' => [{ 'voice_item' => { 'text' => '转写文本', 'aeskey' => 'K', 'url' => 'u' } }] }
    msg = Scinote::WechatGateway::IlinkMessageParser.parse(raw)
    assert_equal :voice, msg.type
    assert_equal '转写文本', msg.media[0][:text]
  end

  def test_file_with_name
    raw = { 'message_type' => 1, 'from_user_id' => 'u',
            'item_list' => [{ 'file_item' => { 'file_name' => 'note.pdf', 'len' => '10', 'aeskey' => 'K' } }] }
    msg = Scinote::WechatGateway::IlinkMessageParser.parse(raw)
    assert_equal :file, msg.type
    assert_equal 'note.pdf', msg.media[0][:file_name]
  end

  def test_group_field_env_changes_user_id
    ENV['ILINK_GROUP_FIELD'] = 'room_id'
    raw = text_and_image_raw.merge('room_id' => 'R1')
    msg = Scinote::WechatGateway::IlinkMessageParser.parse(raw)
    assert_equal 'g.R1.wxuser123', msg.user_id
  ensure
    ENV.delete('ILINK_GROUP_FIELD')
  end
end

class IlinkBridgeTest < Minitest::Test
  class Spy
    attr_reader :calls
    def initialize; @calls = []; end
    def dispatch(platform, msg); @calls << [platform, msg]; end
  end

  def test_run_skips_bot_and_dispatches
    spy = Spy.new
    queue = [
      { 'message_type' => 1, 'from_user_id' => 'u1', 'item_list' => [{ 'text_item' => { 'text' => 'hi' } }] },
      { 'message_type' => 2, 'from_user_id' => 'u1', 'item_list' => [] }, # BOT 自回包
      nil
    ]
    Scinote::WechatGateway::IlinkBridge.run(-> { queue.shift }, handler: spy)
    assert_equal 1, spy.calls.size
    assert_equal :ilink, spy.calls[0][0]
    assert_equal 'u1', spy.calls[0][1].user_id
  end

  def test_inbound_returns_nil_when_unbound
    Scinote::WechatGateway::Inbound.store = FakeStore.new
    raw = { 'message_type' => 1, 'from_user_id' => 'nobody', 'item_list' => [{ 'text_item' => { 'text' => 'x' } }] }
    msg = Scinote::WechatGateway::IlinkMessageParser.parse(raw)
    assert_nil Scinote::WechatGateway::Inbound.dispatch(:ilink, msg)
  end
end
