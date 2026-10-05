module Scinote
  module WechatGateway
    class BindController < ApplicationController
      # HTTP 绑定落地页（备用/二维码场景）。
      # 注意：本页面由浏览器访问，无法识别访问者的微信身份；真正完成绑定仍需
      # 在微信/企微会话中发送「/bind <码>」（消息携带发送者 wechat_id）。
      # 此处仅做绑定码有效性校验并给出指引，避免此前 confirm_by_code 不存在导致的 500。
      def confirm
        code = params[:code].to_s.upcase
        status = BindingResolver.new(Inbound.store).code_status(code)
        case status[:state]
        when :valid
          render plain: "✅ 绑定码有效。\n请回到微信/企微会话，发送「/bind #{code}」完成绑定。\n（本页面无法识别你的微信身份，需通过聊天消息绑定。）"
        when :used
          render plain: "⚠️ 该绑定码已使用，请到 SciNote → 设置 → 微信绑定 重新生成。"
        when :expired
          render plain: "⚠️ 该绑定码已过期，请到 SciNote → 设置 → 微信绑定 重新生成。"
        else
          render plain: "⚠️ 绑定码无效，请确认后重试。"
        end
      end
    end
  end
end
