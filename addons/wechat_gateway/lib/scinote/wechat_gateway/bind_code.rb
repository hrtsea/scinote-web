require 'securerandom'

module Scinote
  module WechatGateway
    # 一次性绑定码：生成时绑定到 SciNote 用户 + 过期时间，消费后作废。
    # store 必须响应：save_code(code, user_id, expires_at) /
    #                  fetch_code(code) -> {user_id:, expires_at:, used:} | nil /
    #                  mark_code_used(code)
    class BindCode
      DEFAULT_TTL = 10 * 60 # 10 分钟

      def initialize(store)
        @store = store
      end

      # 生成绑定码（一次性 + 过期），并把它绑到生成时的 SciNote 用户，防冒领
      CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.freeze # 去 0/O/1/I 歧义

      def generate(scinote_user_id, ttl: DEFAULT_TTL)
        code = 8.times.map { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.length)] }.join
        @store.save_code(code, scinote_user_id, Time.now + ttl)
        code
      end

      # 校验：存在 + 未用 + 未过期 -> 返回 user_id，否则 nil
      def verify(code)
        rec = @store.fetch_code(code)
        return nil unless rec
        return nil if rec[:used]
        return nil if rec[:expires_at] < Time.now
        rec[:user_id]
      end

      # 消费：校验通过后标记已用，返回 user_id（失败返回 nil）
      def consume(code)
        user_id = verify(code)
        return nil unless user_id
        @store.mark_code_used(code)
        user_id
      end
    end
  end
end
