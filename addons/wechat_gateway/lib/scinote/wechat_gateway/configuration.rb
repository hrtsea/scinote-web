module Scinote
  module WechatGateway
    # addon 全局配置：enabled 开关 + 企微/iLink 凭证。
    # 默认启用；可用 ENV 或宿主 initializer 的 configure 块覆盖。
    class Configuration
      attr_accessor :enabled,
                    :wecom_token, :wecom_encoding_aes_key, :wecom_corpid,
                    :ilink_token, :ilink_base_url

      def initialize
        @enabled = true
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
