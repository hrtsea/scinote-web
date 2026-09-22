module Scinote
  module WechatGateway
    # 回调来自企微/微信服务器，无 SciNote session，跳过 CSRF 与登录
    class ApplicationController < ActionController::Base
      skip_before_action :verify_authenticity_token
      skip_before_action :authenticate_user!
    end
  end
end
