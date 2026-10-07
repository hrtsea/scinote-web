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

      # ⚠ CSRF：这里**故意不 skip** authenticity token。
      #   调用点（ResApplyDetail.vue 的动作条、store/ui.js#postForm 的行菜单）都显式带
      #   X-CSRF-Token，token 由宿主 layout 的 csrf_meta_tags 注入，故保持校验不误伤。
      #   留着校验 = fail-closed：将来新增调用点若漏带 header，应当拿到 422，
      #   而不是「SameSite=Lax 恰好挡住 / 恰好漏过」这种不可见的隐式行为。
      #
      #   2026-10-05 修订：这里原本 skip 掉了，注释写的是「安全边界靠 SameSite=Lax +
      #   same-team 闸门 + 只写 addon 自有表」。但 SameSite 只是隐式兜底，skip 之后
      #   漏带 token 的请求没有任何提示，闸门也检查不到 header —— 相当于把兜底拆了。
      #   权限闸门（requestor_authorized? / reviewer_authorized?）照旧独立于 CSRF 生效。

      def create
        result = Scinote::ElnUi::ResourceApplicationWorkflow.call(
          user: current_user,
          team: current_team,
          no: params[:no].to_s,
          type: params[:type].to_s,
          reason: params[:reason].presence,
          receipt: receipt_payload
        )
        render json: result, status: :ok
      rescue Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError => e
        render json: { ok: false, error: e.message }, status: :unprocessable_entity
      end

      private

      # 到货验收的载荷（照片 + 本批数量）。**只在 submit_receipt 时收**，
      # 其余动作带这些参数是噪声（controller 不做「无关参数」的业务判断，交给状态机）。
      #
      # ⚠ 两种提交形态都要支持，因为「照片必传」这条规则决定了这个端点**必然**收到文件：
      #   · multipart（浏览器主路径）：`receipt_photos[]` + `receipt_qty`
      #     —— 前端用 FormData 提交；ActiveStorage 的 attach 由状态机做（它要 record.id）；
      #   · JSON（脚本 / 测试）：`receipt[qty]` + `receipt[photos]`
      # ⚠ 照片**不**在 controller 这里 attach：那会分裂成「controller 建记录、状态机管状态」
      #   两处写记录的生命周期。照片与记录同生共死，交给 `apply_submit_receipt` 一处做。
      def receipt_payload
        return nil unless params[:type].to_s == 'submit_receipt'

        files = Array(params[:receipt_photos]).reject(&:blank?)
        {
          qty: params[:receipt_qty].presence || params.dig(:receipt, :qty),
          photos: files.presence || Array(params.dig(:receipt, :photos))
        }
      end

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
