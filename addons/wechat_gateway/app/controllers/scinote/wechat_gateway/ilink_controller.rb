module Scinote
  module WechatGateway
    class IlinkController < ApplicationController
      # iLink 私聊 DM 回调（消息由 iLink 桥接层转发至此）
      def callback
        WechatGateway::Inbound.dispatch(:ilink, request.body.read)
        head :ok
      end
    end
  end
end
