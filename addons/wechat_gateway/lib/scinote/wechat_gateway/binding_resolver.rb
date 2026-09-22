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
    end
  end
end
