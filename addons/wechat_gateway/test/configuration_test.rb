require 'minitest/autorun'
require_relative '../lib/scinote/wechat_gateway/configuration'

class ConfigurationTest < Minitest::Test
  def test_default_enabled_true
    Scinote::WechatGateway.configuration = nil
    assert Scinote::WechatGateway.enabled?
  end

  def test_configure_block_sets_credentials_and_switch
    Scinote::WechatGateway.configuration = nil
    Scinote::WechatGateway.configure do |c|
      c.enabled = false
      c.wecom_token = 'tok'
      c.wecom_corpid = 'wwabc'
      c.wecom_encoding_aes_key = 'A' * 43
    end
    refute Scinote::WechatGateway.enabled?
    cfg = Scinote::WechatGateway.configuration
    assert_equal 'tok', cfg.wecom_token
    assert_equal 'wwabc', cfg.wecom_corpid
  end

  def test_enabled_reflects_boolean
    Scinote::WechatGateway.configuration = nil
    Scinote::WechatGateway.configuration.enabled = false
    refute Scinote::WechatGateway.enabled?
    Scinote::WechatGateway.configuration.enabled = true
    assert Scinote::WechatGateway.enabled?
  end
end
