# frozen_string_literal: true

module Scinote
  module WechatGateway
    # 媒体下载：把 Message.media 描述符取回为字节流（供 vision / asr / 附件落库复用）。
    # - iLink：descriptor 带 aes_key，走 IlinkBridge.download_media（AES-128-ECB 解密）
    # - 企微：descriptor 带 url/full_url 时直接 GET；仅 media_id 的场景需企微素材接口凭证
    #   （未实现，返回 nil，Ticket 07/08 真机补）
    module Media
      class << self
        attr_writer :http_get

        # descriptor -> String(bytes) | nil
        def fetch(descriptor)
          return nil if descriptor.nil?

          if descriptor[:aes_key].present?
            IlinkBridge.download_media(descriptor, http_get: http_get)
          else
            url = descriptor[:full_url] || descriptor[:url]
            return nil if url.blank?

            http_get.call(url)
          end
        rescue StandardError => e
          warn_log("media fetch failed: #{e.message}")
          nil
        end

        def http_get
          @http_get ||= method(:default_http_get)
        end

        def default_http_get(url)
          require 'uri'
          require 'net/http'
          Net::HTTP.get(URI(url))
        end

        def warn_log(msg)
          Rails.logger.warn("[wechat_gateway] #{msg}") if defined?(Rails)
        end
      end
    end
  end
end
