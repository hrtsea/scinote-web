module Scinote
  module WechatGateway
    class BindController < ApplicationController
      # HTTP 绑定确认入口（主路径为私聊 /bind <码>，此处留作备用/二维码场景）
      def confirm
        binding = WechatGateway::BindingResolver.confirm_by_code(params[:code])
        if binding
          render plain: "OK bound to user #{binding.scinote_user_id}"
        else
          head :not_found
        end
      end
    end
  end
end
