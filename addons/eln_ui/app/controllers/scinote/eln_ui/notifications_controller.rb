# frozen_string_literal: true

module Scinote
  module ElnUi
    # 通知中心端点（REQ-NOTIF / SCN-DASH-7）
    #
    #   GET  /eln_notifications        → { unread, items: [...] } 当前用户全部通知 + 未读计数
    #   PATCH /eln_notifications/:id/read → { ok: true }           标记已读（点开跳转前调一次）
    #
    # 读库走 Noticed 的 Notification 模型（与 NotificationPublisher 写入同表），
    # 不造二开通知表。CSRF 不 skip —— Workbench 调用点显式带 X-CSRF-Token。
    class NotificationsController < ApplicationController
      before_action :require_login

      def index
        render json: Scinote::ElnUi::NotificationsPayload.call(user: current_user)
      end

      def read
        n = ::Notification.where(recipient: current_user, id: params[:id]).first
        if n
          n.update!(read_at: Time.current) if n.read_at.nil?
          render json: { ok: true }
        else
          render json: { ok: false, error: '通知不存在或不属于当前用户' }, status: :not_found
        end
      end

      private

      def require_login
        return if current_user

        redirect_to '/login'
      end
    end
  end
end
