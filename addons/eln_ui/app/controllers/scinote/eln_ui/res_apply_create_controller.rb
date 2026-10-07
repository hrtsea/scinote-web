# frozen_string_literal: true

# ELN UI —— 新建资源申请端点（SCN-RES-APPLY-1 · OPEN-10 收尾）
#
# 单端点 POST /eln_res_applications，body(JSON)：project_id / kind / name /
# qty / unit / unit_price / purpose / repository_id（材料类必填：进入哪个库）——
# 表单直建草稿，编号由 service 自动生成。
# 业务规则全部在 ResourceApplicationWorkflow.create_draft（字段校验 + 编号 +
# 团队口径），这里只做：登录/成员校验 → 调 service → JSON 回包。
#
# 🔴 2026-10-06 语义变更（ADR-0030）：材料类 = **请购单**，不是领用单。
#   参数由 `repository_row_id`（绑定一条**已存在**的库存条目）改为
#   `repository_id`（**进入哪个库**）。两者名字像、语义相反：
#     · 旧 = 料已在库里，去领 → 出库扣减
#     · 新 = 料还没进库，货到了才进 → 入库
#   详见 `docs/adr/0030-material-application-is-procurement.md`。
#
# 错误语义：WorkflowError → 422 { ok:false, error }（表单内红字显示）；
# 未登录跳 /login；无 team 403 —— 与 action controller 同款。
# CSRF：走宿主默认校验（不 skip）；token 由前端 fetch 显式带 X-CSRF-Token。
module Scinote
  module ElnUi
    class ResApplyCreateController < ApplicationController
      before_action :require_login
      before_action :check_team_membership

      # ⚠ 不 skip authenticity token，理由与 ResApplyActionController 同源
      #   （见该文件的 CSRF 注释）：调用点 ResCenter.vue 的「新建申请」显式带
      #   X-CSRF-Token，缺 header 应当 422 而不是静默成功。

      def create
        # ⚠ 踩坑（2026-10-05）：本版 Rails 7.2 的 ActionController::Parameters **没有 expect**
        #   （expect 是别的版本才带的）→ 调它直接 NoMethodError；更狠的是 rescue 里写的
        #   ActionController::ParameterTypeError 在这版**也不存在** → NameError，
        #   一个字段填错就是「NoMethodError → 兜底异常 → 500」的双重崩。
        #   这里一律 permit + 缺键补 nil：类型不硬转，一律交给 service 做业务判定
        #   （service 对 nil / 字符串都有兜底：blank? / to_d / to_s.strip）。
        permitted = params.permit(:project_id, :kind, :name, :qty, :unit, :unit_price,
                                  :purpose, :service_catalog_id, :my_module_id, :repository_id)
        attrs = permitted.to_h.symbolize_keys
        %i[project_id kind name qty unit unit_price purpose service_catalog_id my_module_id repository_id].each do |key|
          attrs[key] = nil unless attrs.key?(key)
        end

        # fail-closed：project_id 若已填，必须属于当前用户可读且未归档的项目集合
        # （与资源中心下拉同源 —— ProjectListScope#for_listing(view_mode: 'active')）。
        # 缺失（pid=0）不动，交由 service 抛「请选择申请项目」，保留既有语义与测试。
        pid = attrs[:project_id].to_i
        unless pid.zero?
          allowed_project_ids = Scinote::ElnUi::ProjectListScope
                                .for_listing(team: current_team, user: current_user, view_mode: 'active')
                                .pluck(:id)
          unless allowed_project_ids.include?(pid)
            render json: { ok: false, error: '无权限选择该项目或项目已归档' },
                   status: :unprocessable_entity
            return
          end
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
