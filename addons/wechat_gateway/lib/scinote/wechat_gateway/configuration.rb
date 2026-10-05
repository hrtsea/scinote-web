module Scinote
  module WechatGateway
    # addon 全局配置：enabled 开关 + 企微/iLink 凭证。
    # 默认启用；可用 ENV 或宿主 initializer 的 configure 块覆盖。
    class Configuration
      attr_accessor :enabled,
                    :wecom_token, :wecom_encoding_aes_key, :wecom_corpid,
                    :ilink_token, :ilink_base_url,
                    :default_project_id, :vision_endpoint,
                    :ai_enabled, :ai_endpoint, :ai_api_key, :ai_model,
                    :ilink_reply_sender

      def initialize
        @enabled = true
        # iLink 出站回包钩子：proc(user_id, text) -> void。默认 nil（仅记录，待接 iLink 主动消息 API）。
        @ilink_reply_sender = nil
      end
    end

    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      # 宿主 initializer 中调用：Scinote::WechatGateway.configure { |c| c.wecom_token = ... }
      def configure
        yield(configuration) if block_given?
      end

      def enabled?
        !!(configuration&.enabled)
      end
    end
  end
end
