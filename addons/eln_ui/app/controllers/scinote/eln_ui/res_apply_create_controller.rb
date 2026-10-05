# frozen_string_literal: true

# ELN UI —— 新建资源申请端点（SCN-RES-APPLY-1 · OPEN-10 收尾）
#
# 单端点 POST /eln_res_applications，body(JSON)：project_id / kind / name /
# qty / unit / unit_price / purpose —— 表单直建草稿，编号由 service 自动生成。
# 业务规则全部在 ResourceApplicationWorkflow.create_draft（字段校验 + 编号 +
# 团队口径），这里只做：登录/成员校验 → 调 service → JSON 回包。
#
# 错误语义：WorkflowError → 422 { ok:false, error }（表单内红字显示）；
# 未登录跳 /login；无 team 403 —— 与 action controller 同款。
# CSRF skip 的安全边界说明照抄 ResApplyActionController（登录态 cookie +
# same-team 闸门 + 只写 addon 自有表；fetch 已带 X-CSRF-Token 预留）。
module Scinote
  module ElnUi
    class ResApplyCreateController < ApplicationController
      before_action :require_login
      before_action :check_team_membership

      skip_before_action :verify_authenticity_token, only: [:create]

      def create
        # ⚠ 踩坑（2026-10-05）：本版 Rails 7.2 的 ActionController::Parameters **没有 expect**
        #   （expect 是别的版本才带的）→ 调它直接 NoMethodError；更狠的是 rescue 里写的
        #   ActionController::ParameterTypeError 在这版**也不存在** → NameError，
        #   一个字段填错就是「NoMethodError → 兜底异常 → 500」的双重崩。
        #   这里一律 permit + 缺键补 nil：类型不硬转，一律交给 service 做业务判定
        #   （service 对 nil / 字符串都有兜底：blank? / to_d / to_s.strip）。
        permitted = params.permit(:project_id, :kind, :name, :qty, :unit, :unit_price, :purpose)
        attrs = permitted.to_h.symbolize_keys
        %i[project_id kind name qty unit unit_price purpose].each do |key|
          attrs[key] = nil unless attrs.key?(key)
        end

        result = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
          user: current_user,
          team: current_team,
          **attrs
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
