# frozen_string_literal: true

require 'rails_helper'

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

module Scinote
  module WechatGateway
    RSpec.describe 'Binding layer' do
      let(:store) { FakeStore.new }
      let(:resolver) { BindingResolver.new(store) }
      let(:codes) { BindCode.new(store) }
      let(:cmd) { BindCommand.new(store) }

      it 'generate -> bind -> resolve' do
        code = codes.generate(42)
        expect(codes.verify(code)).to eq(42)
        expect(resolver.bound?('wx_abc', 'ilink')).to be false

        res = cmd.call('wx_abc', 'ilink', "/bind #{code}")
        expect(res[:ok]).to be(true), res[:reply]
        expect(resolver.resolve('wx_abc', 'ilink')).to eq(42)
      end

      it 'code is one-time' do
        code = codes.generate(42)
        expect(codes.consume(code)).to eq(42)
        expect(codes.verify(code)).to be_nil, '消费后再次校验应返回 nil'
      end

      it 'rejects expired code' do
        code = codes.generate(42, ttl: -1)
        expect(codes.verify(code)).to be_nil
      end

      it 'replies on invalid code' do
        res = cmd.call('wx_x', 'ilink', '/bind NOPE')
        expect(res[:ok]).to be false
        expect(res[:reply]).to match(/无效或已过期/)
      end

      it 'keeps original user when already bound' do
        code = codes.generate(42)
        cmd.call('wx_x', 'ilink', "/bind #{code}")

        code2 = codes.generate(99)
        res = cmd.call('wx_x', 'ilink', "/bind #{code2}")
        expect(res[:ok]).to be false
        expect(res[:reply]).to match(/已经绑定/)
        expect(resolver.resolve('wx_x', 'ilink')).to eq(42)
      end

      it 'replies on bad format' do
        res = cmd.call('wx_x', 'ilink', '随便说点')
        expect(res[:ok]).to be false
        expect(res[:reply]).to match(/格式/)
      end

      describe 'code_status' do
        it 'valid 码返回 state :valid 与绑定用户' do
          code = codes.generate(42)
          expect(resolver.code_status(code)).to eq(state: :valid, user_id: 42)
        end

        it '已消费码返回 :used' do
          code = codes.generate(42)
          codes.consume(code)
          expect(resolver.code_status(code)[:state]).to eq(:used)
        end

        it '过期码返回 :expired' do
          code = codes.generate(42, ttl: -1)
          expect(resolver.code_status(code)[:state]).to eq(:expired)
        end

        it '不存在的码返回 :none' do
          expect(resolver.code_status('ZZZZZZZZ')[:state]).to eq(:none)
        end
      end
    end
  end
end
