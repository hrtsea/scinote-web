# frozen_string_literal: true

# ELN UI —— 任务关闭审核写操作端点（REQ-TASK-CLOSE / SCN-TASK-CLOSE-1..4）
#
# 单端点 POST /eln_task_close/:my_module_id/actions，body: type + reason
#   submit  提交完成申请（同团队成员）
#   approve 审核通过并关闭（**仅项目负责人**）
#   reject  驳回并填理由（**仅项目负责人**，理由必填）
#
# 与资源申请端点（ResApplyActionController）刻意同款：登录/成员校验 → 调 workflow →
# JSON 回包，WorkflowError 一律 422 { ok:false, error }。两条流程共用
# Scinote::ElnUi::Workflow 骨架，所以这里的 rescue 也和那边是同一个错误类。
#
# ⚠ CSRF 不 skip：调用点（任务详情审核条）显式带 X-CSRF-Token，token 由宿主 layout 注入。
#   漏带的调用方应当拿到 422，而不是靠 SameSite 隐式兜底。
module Scinote
  module ElnUi
    class TaskCloseActionController < ApplicationController
      before_action :require_login
      before_action :check_team_membership

      def create
        result = Scinote::ElnUi::TaskCloseWorkflow.call(
          user: current_user,
          team: current_team,
          my_module_id: params[:my_module_id],
          type: params[:type].to_s,
          reason: params[:reason].presence
        )
        render json: result, status: :ok
      rescue Scinote::ElnUi::Workflow::WorkflowError => e
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
