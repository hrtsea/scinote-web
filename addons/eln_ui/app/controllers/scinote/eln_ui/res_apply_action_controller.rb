# frozen_string_literal: true

# ELN UI —— 资源申请单写操作端点（OPEN-10）
#
# 单端点 POST /eln_res_apply/:no/actions，body: type + reason：
#   submit / approve_group / approve_project / reject / complete
# 业务规则全部在 ResourceApplicationWorkflow（状态机 + 权限闸门），
# 这里只做：登录/成员校验 → 调 service → JSON 回包。
#
# 错误语义：WorkflowError → 422 { ok:false, error }（页面 toast 显示）；
# 未登录跳 /login；无 team 403 —— 与 GET 侧两个 controller 同款。
module Scinote
  module ElnUi
    class ResApplyActionController < ApplicationController
      before_action :require_login
      before_action :check_team_membership

      skip_before_action :verify_authenticity_token, only: [:create]
      # ⚠ 上面的 skip 是给 fetch JSON 调用开的口子。安全边界不靠 CSRF token，
      #   靠：登录态 cookie（SameSite=Lax）+ same-team/own-application 闸门 +
      #   只写 addon 自有表。若后续宿主收紧 SameSite 策略，这里要同步加
      #   X-CSRF-Token 校验（前端 fetch 已预留读取 meta csrf-token）。

      def create
        result = Scinote::ElnUi::ResourceApplicationWorkflow.call(
          user: current_user,
          team: current_team,
          no: params[:no].to_s,
          type: params[:type].to_s,
          reason: params[:reason].presence
        )
        render json: result, status: :ok
      rescue Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError => e
        render json: { ok: false, error: e.message }, status: :unprocessable_entity
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
    end
  end
end
