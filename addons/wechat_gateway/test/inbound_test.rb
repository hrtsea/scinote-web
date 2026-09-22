require 'minitest/autorun'
require 'securerandom'
require 'base64'
require 'digest'
require_relative '../lib/scinote/wechat_gateway/message'
require_relative '../lib/scinote/wechat_gateway/wecom_crypto'
require_relative '../lib/scinote/wechat_gateway/wecom_message_parser'
require_relative '../lib/scinote/wechat_gateway/binding_resolver'
require_relative '../lib/scinote/wechat_gateway/inbound'

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

def make_aeskey
  key = SecureRandom.random_bytes(32)
  Base64.strict_encode64(key)[0, 43]
end

# 加密 inner XML -> 外层 <xml><Encrypt> + 计算 msg_signature
def wrap_wecom(corpid, aeskey, token, inner_xml)
  enc = Scinote::WechatGateway::WecomCrypto.encrypt(inner_xml, corpid, aeskey)
  outer = "<xml><ToUserName><![CDATA[#{corpid}]]></ToUserName>" \
          "<Encrypt><![CDATA[#{enc}]></Encrypt></xml>"
  sig = Digest::SHA1.hexdigest([token, '1700000000', 'n0nce', enc].sort.join)
  [outer, { timestamp: '1700000000', nonce: 'n0nce', msg_signature: sig }]
end

def text_inner(corpid, content)
  "<xml><ToUserName><![CDATA[#{corpid}]]></ToUserName>" \
  "<FromUserName><![CDATA[u_wx_123]]></FromUserName>" \
  "<CreateTime>1700000000</CreateTime>" \
  "<MsgType><![CDATA[text]]></MsgType>" \
  "<Content><![CDATA[#{content}]]></Content><MsgId>99</MsgId></xml>"
end

class WecomMessageParserTest < Minitest::Test
  def corpid = 'ww1234567890abcdef'

  def test_parse_text
    m = Scinote::WechatGateway::WecomMessageParser.parse(text_inner(corpid, '实验记录 🚀'))
    assert_equal 'u_wx_123', m.user_id
    assert_equal '实验记录 🚀', m.text
    assert_equal :text, m.type
    assert_equal :wecom, m.platform
    assert_equal 1_700_000_000, m.timestamp
  end

  def test_parse_image_has_media
    xml = text_inner(corpid, 'x').sub(
      '<MsgType><![CDATA[text]]></MsgType><Content><![CDATA[x]]></Content>',
      '<MsgType><![CDATA[image]]></MsgType><MediaId><![CDATA[mid_1]]></MediaId>' \
      '<PicUrl><![CDATA[https://cdn/p]]></PicUrl>'
    )
    m = Scinote::WechatGateway::WecomMessageParser.parse(xml)
    assert_equal :image, m.type
    assert_equal 1, m.media.size
    assert_equal :image, m.media[0][:kind]
    assert_equal 'mid_1', m.media[0][:media_id]
    assert_equal 'https://cdn/p', m.media[0][:url]
  end

  def test_parse_event_text
    xml = text_inner(corpid, 'x').sub(
      '<MsgType><![CDATA[text]]></MsgType><Content><![CDATA[x]]></Content>',
      '<MsgType><![CDATA[event]]></MsgType><Event><![CDATA[subscribe]]></Event>' \
      '<EventKey><![CDATA[ek1]]></EventKey>'
    )
    m = Scinote::WechatGateway::WecomMessageParser.parse(xml)
    assert_equal :event, m.type
    assert_equal 'subscribe:ek1', m.text
  end
end

class InboundReceiveTest < Minitest::Test
  def setup
    @corpid = 'ww1234567890abcdef'
    @aeskey = make_aeskey
    @token = 'mytoken'
    Scinote::WechatGateway::WecomCrypto.config = {
      token: @token, encoding_aes_key: @aeskey, receive_id: @corpid
    }
    @store = FakeStore.new
    Scinote::WechatGateway::Inbound.store = @store
    Scinote::WechatGateway::Inbound.intake_handler = ->(uid, msg) { "intake:#{uid}:#{msg.text}" }
    @inner = text_inner(@corpid, '实验记录 🚀')
  end

  def test_receive_bound_dispatches_to_intake
    @store.create_binding(42, 'u_wx_123', :wecom)
    outer, params = wrap_wecom(@corpid, @aeskey, @token, @inner)
    res = Scinote::WechatGateway::Inbound.receive(:wecom, outer, params)
    assert res[:bound]
    assert_equal 42, res[:user_id]
    assert_equal '实验记录 🚀', res[:message].text
    assert_equal :wecom, res[:message].platform
    assert_equal 'intake:42:实验记录 🚀', res[:intake]
  end

  def test_receive_unbound_returns_guidance
    outer, params = wrap_wecom(@corpid, @aeskey, @token, @inner)
    res = Scinote::WechatGateway::Inbound.receive(:wecom, outer, params)
    refute res[:bound]
    assert_nil res[:user_id]
    assert res[:guidance]
  end

  def test_dispatch_contract_unchanged
    # 绑定时返回 user_id
    @store.create_binding(42, 'u_wx_123', :wecom)
    outer, params = wrap_wecom(@corpid, @aeskey, @token, @inner)
    msg = Scinote::WechatGateway::Inbound.parse(:wecom, outer, params)
    assert_equal 42, Scinote::WechatGateway::Inbound.dispatch(:wecom, msg)
    # 未绑定时返回 nil（ticket 05 的 ilink_test.rb 依赖此契约）
    Scinote::WechatGateway::Inbound.store = FakeStore.new
    msg2 = Scinote::WechatGateway::Inbound.parse(:wecom, outer, params)
    assert_nil Scinote::WechatGateway::Inbound.dispatch(:wecom, msg2)
  end
end
