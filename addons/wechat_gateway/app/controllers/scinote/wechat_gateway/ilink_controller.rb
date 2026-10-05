module Scinote
  module WechatGateway
    class IlinkController < ApplicationController
      # iLink 私聊 DM 回调（消息由 iLink 桥接层转发至此）
      def callback
        raw = JSON.parse(request.body.read)
        result = WechatGateway::Inbound.receive(:ilink, raw, {})
        reply = result[:reply] || (result[:bound] ? result[:intake] : result[:guidance])
        if reply && result[:message]
          # iLink 无标准被动回包，需经主动消息 API 发送；v1 先走可注入钩子，未配置则仅记录。
          sender = WechatGateway.configuration.ilink_reply_sender
          if sender.respond_to?(:call)
            sender.call(result[:message].user_id, reply)
          else
            Rails.logger.info(
              "[wechat_gateway] ilink reply (sender 未配置，仅记录) " \
              "user=#{result[:message].user_id} reply=#{reply.inspect}"
            )
          end
        end
        head :ok
      rescue JSON::ParserError => e
        Rails.logger.warn("[wechat_gateway] ilink bad json: #{e.message}")
        head :bad_request
      end
    end
  end
end
