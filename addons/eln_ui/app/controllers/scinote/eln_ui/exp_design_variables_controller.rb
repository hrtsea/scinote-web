# frozen_string_literal: true

# ELN UI —— 实验级 DOE 设计变量（DV）行级 CRUD（ADR-0051 Q4=b / Q8=a / Q9=a）
#
# 纯二开表 eln_ui_design_variables，原生无对应物。本控制器只做「变量表本身的
# 增 / 改 / 删」—— 不碰「场景A/B 切换」「重新计算贝叶斯」「一键生成验证任务」那
# 三个 AI 按钮（需后端 AI 服务，另立项）。
#
# 权限：ExperimentPermissions::MANAGE（与实验详情 design 子页签显隐同源）。
# 域收口：变量必须落在**当前实验**下，跨实验 id 一律 404（不泄漏存在性）。
# position：创建时 append 到末尾（max+1），不做拖拽重排（Q9=a）。
# 响应：{ expDesignVars: [...] }（与 ExpDetailPayload#exp_design_vars 同源 shape，
#   前端就地 replaceList，不跳页、留在 design 子页签）。

module Scinote
  module ElnUi
    class ExpDesignVariablesController < ApplicationController
      before_action :set_experiment
      before_action :check_manage

      def create
        var = Scinote::ElnUi::DesignVariable.new(
          dv_params.merge(experiment_id: @experiment.id, position: next_position)
        )
        var.save!
        render json: vars_after
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      def update
        var = find_var
        var.update!(dv_params)
        render json: vars_after
      rescue ActiveRecord::RecordNotFound
        render_404
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      def destroy
        var = find_var
        var.destroy!
        render json: vars_after
      rescue ActiveRecord::RecordNotFound
        render_404
      end

      private

      # 可读性先用原生 readable_by_user 守（不能读这个实验就谈不上改它的变量）；
      # 再判 MANAGE（见 check_manage）。跨实验 id / 不可读 → 404，不泄漏存在性。
      def set_experiment
        @experiment = Experiment.readable_by_user(current_user).find_by(id: params[:experiment_id])
        render_404 unless @experiment
      end

      def check_manage
        return if @experiment.permission_granted?(current_user, ExperimentPermissions::MANAGE)

        render_403
      end

      def find_var
        Scinote::ElnUi::DesignVariable.find_by!(experiment_id: @experiment.id, id: params[:id])
      end

      # 创建时 append：position = 当前最大+1（Q9=a，不做重排）。
      def next_position
        (Scinote::ElnUi::DesignVariable.where(experiment_id: @experiment.id).maximum(:position) || 0) + 1
      end

      def dv_params
        # ⚠ 不能用 params.expect（那是 Rails 8 才有的 API，本项目 Rails 7.2 没有该方法）。
        params.require(:design_variable)
              .permit(:name, :var_type, :range_min, :range_max, :unit, :constraint)
      end

      # 与 ExpDetailPayload#exp_design_vars 同源 shape（display 用 range + 原始字段）。
      # 直接委托 payload —— range_text/format_number/表存在性兜底都由 payload 一处维护，
      # 不在 controller 再抄一份（避免两份逻辑漂移）。
      def vars_after
        { expDesignVars: Scinote::ElnUi::ExpDetailPayload.new(@experiment, user: current_user).exp_design_vars }
      end
    end
  end
end
