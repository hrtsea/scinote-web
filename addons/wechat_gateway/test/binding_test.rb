require 'minitest/autorun'
require_relative '../lib/scinote/wechat_gateway/binding_resolver'
require_relative '../lib/scinote/wechat_gateway/bind_code'
require_relative '../lib/scinote/wechat_gateway/bind_command'

# 脱离 Rails 的内存存储桩，覆盖 BindingResolver / BindCode / BindCommand 的接口
class FakeStore
  def initialize
    @bindings = {} # "wechat_id:platform" => user_id
    @codes = {}    # code => {user_id:, expires_at:, used:}
  end

  def find_binding(wechat_id, platform)
    @bindings["#{wechat_id}:#{platform}"]
  end

  def create_binding(user_id, wechat_id, platform)
    @bindings["#{wechat_id}:#{platform}"] = user_id
    true
  end

  def save_code(code, user_id, expires_at)
    @codes[code] = { user_id: user_id, expires_at: expires_at, used: false }
  end

  def fetch_code(code)
    @codes[code]
  end

  def mark_code_used(code)
    @codes[code][:used] = true if @codes[code]
  end
end

class BindingTest < Minitest::Test
  def setup
    @store = FakeStore.new
    @resolver = Scinote::WechatGateway::BindingResolver.new(@store)
    @codes = Scinote::WechatGateway::BindCode.new(@store)
    @cmd = Scinote::WechatGateway::BindCommand.new(@store)
  end

  def test_generate_then_bind_then_resolve
    code = @codes.generate(42)
    assert_equal 42, @codes.verify(code)
    refute @resolver.bound?('wx_abc', 'ilink')

    res = @cmd.call('wx_abc', 'ilink', "/bind #{code}")
    assert res[:ok], res[:reply]
    assert_equal 42, @resolver.resolve('wx_abc', 'ilink')
  end

  def test_code_is_one_time
    code = @codes.generate(42)
    assert_equal 42, @codes.consume(code)
    assert_nil @codes.verify(code), '消费后再次校验应返回 nil'
  end

  def test_expired_code
    code = @codes.generate(42, ttl: -1) # 已过期
    assert_nil @codes.verify(code)
  end

  def test_invalid_code_reply
    res = @cmd.call('wx_x', 'ilink', '/bind NOPE')
    refute res[:ok]
    assert_match(/无效或已过期/, res[:reply])
  end

  def test_already_bound_keeps_original_user
    code = @codes.generate(42)
    @cmd.call('wx_x', 'ilink', "/bind #{code}")

    code2 = @codes.generate(99)
    res = @cmd.call('wx_x', 'ilink', "/bind #{code2}")
    refute res[:ok]
    assert_match(/已经绑定/, res[:reply])
    assert_equal 42, @resolver.resolve('wx_x', 'ilink')
  end

  def test_bad_format_reply
    res = @cmd.call('wx_x', 'ilink', '随便说点')
    refute res[:ok]
    assert_match(/格式/, res[:reply])
  end
end
