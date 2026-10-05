module Scinote
  module WechatGateway
    # /bind <码> 指令处理：解析 → 校验（已绑定/失效）→ 建绑定 → 回执。
    # 与通道无关：调用方传入 (wechat_id, platform, text)，由 store 落地。
    class BindCommand
      def initialize(store)
        @store = store
        @resolver = BindingResolver.new(store)
        @codes = BindCode.new(store)
      end

      # 返回 { ok: bool, reply: String }
      def call(wechat_id, platform, text)
        code = parse_code(text)
        return { ok: false, reply: '绑定格式：/bind <你的绑定码>' } if code.nil?

        if @resolver.bound?(wechat_id, platform)
          return { ok: false, reply: '这个微信/企微账号已经绑定过啦，无需重复绑定。' }
        end

        user_id = @codes.consume(code)
        if user_id.nil?
          return { ok: false, reply: '绑定码无效或已过期，请在 SciNote 设置页重新获取。' }
        end

        begin
          @store.create_binding(user_id, wechat_id, platform)
        rescue StandardError => e
          # 极少数竞态/重复绑定：回滚已消费的码不可行，给出明确提示而非 500
          return { ok: false, reply: "绑定失败：#{e.message}。如已绑定请忽略，否则联系管理员。" }
        end
        { ok: true, reply: '绑定成功！以后直接用微信/企微给我发实验记录即可 🎉' }
      end

      private

      def parse_code(text)
        m = text.to_s.strip.match(/\A\/bind\s+([A-Za-z0-9]{4,12})\z/)
        m && m[1].upcase
      end
    end
  end
end
