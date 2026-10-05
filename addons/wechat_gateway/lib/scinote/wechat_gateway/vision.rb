# frozen_string_literal: true

require 'json'

module Scinote
  module WechatGateway
    # 视觉识别（Ticket 05）：图片 -> 文本，用于把识别结果追加进正文。
    # 按 plan §15，本地视觉模型以 sidecar 暴露 HTTP 端点，addon 内部 POST 调用。
    # 端点由 config.vision_endpoint（ENV VISION_ENDPOINT）配置；未配置即禁用。
    # 依赖注入：fetcher（descriptor -> bytes）、http_post（endpoint, bytes -> response body），
    # 便于无实例 / 无模型单测。
    module Vision
      class << self
        attr_writer :fetcher, :http_post

        def enabled?
          Scinote::WechatGateway.configuration.vision_endpoint.present?
        end

        # descriptor -> String | nil（识别失败/未启用返回 nil，调用方降级为仅附件）
        def describe(descriptor)
          return nil unless enabled?

          bytes = fetcher.call(descriptor)
          return nil if bytes.nil?

          parse_text(http_post.call(endpoint, bytes, descriptor))
        rescue StandardError => e
          warn_log("vision describe failed: #{e.message}")
          nil
        end

        def endpoint
          Scinote::WechatGateway.configuration.vision_endpoint
        end

        def fetcher
          @fetcher ||= Media.method(:fetch)
        end

        def http_post
          @http_post ||= method(:default_http_post)
        end

        def default_http_post(url, bytes, _descriptor)
          require 'uri'
          require 'net/http'
          uri = URI(url)
          req = Net::HTTP::Post.new(uri)
          req['Content-Type'] = 'application/octet-stream'
          req.body = bytes
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }.body
        end

        # 兼容 {text:} / {description:} / 纯字符串响应
        def parse_text(response)
          return response.to_s.strip.presence unless response.is_a?(String)

          data = JSON.parse(response)
          (data['text'] || data['description'] || data['result']).to_s.strip.presence
        rescue JSON::ParserError
          response.to_s.strip.presence
        end

        def warn_log(msg)
          Rails.logger.warn("[wechat_gateway] #{msg}") if defined?(Rails)
        end
      end
    end
  end
end
