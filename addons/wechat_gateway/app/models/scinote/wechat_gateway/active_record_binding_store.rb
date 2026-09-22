module Scinote
  module WechatGateway
    # 真实存储后端：绑定落到 wechat_user_bindings 表；绑定码放 Rails.cache（免新迁移）。
    # 仅在 Rails 运行时使用；单测用内存 FakeStore 注入，不依赖本类。
    class ActiveRecordBindingStore
      CACHE_NS = 'wechat_gateway:bind_code:'.freeze

      def find_binding(wechat_id, platform)
        WechatUserBinding.for(wechat_id, platform).pick(:scinote_user_id)
      end

      def create_binding(user_id, wechat_id, platform)
        WechatUserBinding.create!(
          scinote_user_id: user_id, wechat_id: wechat_id, platform: platform
        )
      end

      def save_code(code, user_id, expires_at)
        Rails.cache.write(
          cache_key(code),
          { user_id: user_id, expires_at: expires_at, used: false },
          expires_in: (expires_at - Time.now).to_i + 5
        )
      end

      def fetch_code(code)
        Rails.cache.read(cache_key(code))
      end

      def mark_code_used(code)
        rec = Rails.cache.read(cache_key(code))
        return unless rec
        Rails.cache.write(cache_key(code), rec.merge(used: true))
      end

      private

      def cache_key(code)
        CACHE_NS + code.to_s
      end
    end
  end
end
