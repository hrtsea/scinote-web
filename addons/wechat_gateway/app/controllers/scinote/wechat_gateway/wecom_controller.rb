module Scinote
  module WechatGateway
    class WecomController < ApplicationController
      # 企微回调入口：GET 校验 URL（配置时），POST 收消息
      def callback
        if request.get?
          render plain: WechatGateway::WecomCrypto.verify_url(params)
        else
          result = WechatGateway::Inbound.receive(:wecom, request.body.read, params)
          reply = result[:reply] || (result[:bound] ? result[:intake] : result[:guidance])
          if reply && result[:message]
            # 企微被动回复：5 秒内同步回包，收发方互换
            from = WechatGateway::WecomCrypto.config[:receive_id]
            xml = WechatGateway::WecomReply.text(
              result[:message].user_id, from, WechatGateway::WecomReply.truncate(reply)
            )
            render xml: xml
          else
            head :ok
          end
        end
      end
    end
  end
end
