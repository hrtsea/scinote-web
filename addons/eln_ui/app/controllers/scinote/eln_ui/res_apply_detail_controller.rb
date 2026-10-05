# frozen_string_literal: true

# ELN UI —— 资源申请详情页（按 Vue3 原型 ELN系统-Vue3/src/views/ResApplyDetail.vue 重建）
#
# 形状与 ResCenterController 同：宿主 layout + JSON 注入 + 挂载点。
# 单条详情（按业务编号 SQ-YYYY-NNNN 查），权限卡在「项目可见性」。
#
# 404 / 403 的语义走 service 返回的 { notFound: true } / { forbidden: true }：
# 不在 controller 里 raise（避免和原生全局错误页分叉）。
module Scinote
  module ElnUi
    class ResApplyDetailController < ApplicationController
      before_action :require_login
      before_action :check_team_membership

      def show
        @payload_json = JSON.generate(payload).gsub('<', '\\u003c')
      end

      private

      def require_login
        return if current_user

        redirect_to '/login'
      end

      def check_team_membership
        return if current_team

        render_403 and return
      end

      def payload
        Scinote::ElnUi::ResApplyDetailPayload.call(
          user: current_user,
          team: current_team,
          no: params[:no].to_s
        )
      end
    end
  end
end
