module Scinote
  module WechatGateway
    # 按 (wechat_id, platform) 解析已绑定的 SciNote 用户。
    # store 必须响应 find_binding(wechat_id, platform) -> scinote_user_id | nil
    class BindingResolver
      def initialize(store)
        @store = store
      end

      def resolve(wechat_id, platform)
        @store.find_binding(wechat_id, platform)
      end

      def bound?(wechat_id, platform)
        !resolve(wechat_id, platform).nil?
      end

      # 绑定码状态查询（供 HTTP /bind/:code 落地页使用）：
      #   :valid  存在 + 未用 + 未过期
      #   :used   已消费
      #   :expired 已过期
      #   :none   不存在
      def code_status(code)
        rec = @store.fetch_code(code)
        return { state: :none } unless rec
        return { state: :used } if rec[:used]
        return { state: :expired } if rec[:expires_at] < Time.now

        { state: :valid, user_id: rec[:user_id] }
      end
    end
  end
end
