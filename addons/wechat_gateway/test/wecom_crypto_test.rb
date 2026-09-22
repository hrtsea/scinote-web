require 'minitest/autorun'
require_relative '../lib/scinote/wechat_gateway/wecom_crypto'

# 脱离 Rails 的可执行单测：ruby test/wecom_crypto_test.rb
class WecomCryptoTest < Minitest::Test
  def setup
    key = SecureRandom.random_bytes(32)
    @encoding_aes_key = Base64.strict_encode64(key)[0, 43] # 43 字符 EncodingAESKey
    @receive_id = 'ww1234567890abcdef'
  end

  def test_roundtrip_ascii_and_unicode
    ['hello wecom', '实验记录 🚀 中文'].each do |msg|
      enc = Scinote::WechatGateway::WecomCrypto.encrypt(msg, @receive_id, @encoding_aes_key)
      assert_equal msg,
                   Scinote::WechatGateway::WecomCrypto.decrypt(enc, @encoding_aes_key, @receive_id)
    end
  end

  def test_signature_valid_and_tampered
    token = 'mytoken'
    ts = '1700000000'
    nonce = 'abc'
    encrypt = Base64.strict_encode64('x')
    sig = Digest::SHA1.hexdigest([token, ts, nonce, encrypt].sort.join)
    assert Scinote::WechatGateway::WecomCrypto.verify_signature(token, ts, nonce, encrypt, sig)
    refute Scinote::WechatGateway::WecomCrypto.verify_signature(token, ts, nonce, encrypt, 'deadbeef')
  end

  def test_receive_id_mismatch_raises
    msg = 'hi'
    enc = Scinote::WechatGateway::WecomCrypto.encrypt(msg, @receive_id, @encoding_aes_key)
    assert_raises(RuntimeError) do
      Scinote::WechatGateway::WecomCrypto.decrypt(enc, @encoding_aes_key, 'wrong-corpid')
    end
  end

  def test_decrypt_callback_roundtrip
    msg = '群消息内容'
    enc = Scinote::WechatGateway::WecomCrypto.encrypt(msg, @receive_id, @encoding_aes_key)
    sig = Digest::SHA1.hexdigest(['tok', '123', 'n', enc].sort.join)
    xml = "<xml><ToUserName><![CDATA[to]]></ToUserName><Encrypt><![CDATA[#{enc}]]></Encrypt></xml>"
    Scinote::WechatGateway::WecomCrypto.config = {
      token: 'tok', encoding_aes_key: @encoding_aes_key, receive_id: @receive_id
    }
    params = { timestamp: '123', nonce: 'n', msg_signature: sig }
    assert_equal msg, Scinote::WechatGateway::WecomCrypto.decrypt_callback(xml, params)
  end
end
