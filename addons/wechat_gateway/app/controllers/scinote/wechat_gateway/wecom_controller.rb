module Scinote
  module WechatGateway
    class WecomController < ApplicationController
      # 企微回调入口：GET 校验 URL（配置时），POST 收消息
      def callback
        if request.get?
          render plain: WechatGateway::WecomCrypto.verify_url(params)
        else
          raw_msg = WechatGateway::WecomCrypto.decrypt(request.body.read, params)
          WechatGateway::Inbound.dispatch(:wecom, raw_msg)
          head :ok
        end
      end
    end
  end
end
