# frozen_string_literal: true

# ELN UI —— 实验详情页（按 Vue3 原型重建的第三页）
#
# 与另两个 controller 同一套样板：侧栏/顶栏/布局容器走 SciNote 原生，
# 内容区只留一个挂载点 #eln-exp-detail，交给 ELN系统-Vue3/src/entries/exp_detail.js
# 的 bundle 接管；数据由 ExpDetailPayload 出，以 JSON 块注入，没有第二个数据源。
#
# 与列表/详情页不同的两件事：
#   1. 原生**没有** experiments/show 页面 —— 实验详情就是任务列表 my_modules#index。
#      这条事实限制了落点：本页不能声称「替换了原生实验页」，只能说在原生之外
#      另起一个 ELN 视角的实验页，原生那个入口仍然在那儿（PRD §7.7 首段已点明）。
#   2. 除了「我能不能读这个实验」，还要决定子页签里「实验设计与配方优化」给不给
#      （DEC-001 组员不可见）—— 这是本页唯一的权限裁剪点。
module Scinote
  module ElnUi
    class ExpDetailController < ApplicationController
      def index
        experiment
        @payload_json = JSON.generate(payload).gsub('<', '\\u003c')
      end

      # ------------------------------------------------------------
      # 编辑实验信息（ADR-0051）：实验信息 / 目的 / 方法 / 状态 可写。
      # 闸 = MANAGE（与 design 子页签显隐同源，避免「看得见按钮、保存 403」分叉）。
      # 原生字段 name/due_date + 虚拟 status（TimeTrackable 三态机写 started_at/done_at）
      # 直接落 experiments；二开 business_code/owner_user_id/purpose/method 走 profile upsert。
      # 所属项目 / 任务进度 不在白名单（原生无承载，保持只读，见 ADR-0051 §2）。
      # 返回**全量 payload**（前端 window.location.reload() 同源，不解析 body）。
      # ------------------------------------------------------------
      def update
        exp = experiment # 设 @experiment 且守可读性（不可读 → 404）
        return render_403 unless can_manage_experiment?

        native_attrs = experiment_params.slice(:name, :due_date).to_h.compact
        profile_attrs = experiment_params.slice(:business_code, :purpose, :method).to_h.compact
        # owner_user_id 显式处理：前端在「负责人」下拉选「不指定」时发 null，
        # 必须落到 nil 清掉显式负责人。compact 会吞掉 nil，故单独处理——
        # 只在请求**显式带了这个 key** 时才动它（不带则保留原值）。
        profile_attrs[:owner_user_id] = experiment_params[:owner_user_id].presence if experiment_params.key?(:owner_user_id)
        status = experiment_params[:status].presence

        # status 直发 trackable 形态（not_started/in_progress/done）；非法值忽略不写。
        # 有效性判定复用 ExpDetailPayload::STATUS_TRACKABLE 的 values（单一来源）。
        native_attrs[:status] = status if status && Scinote::ElnUi::ExpDetailPayload::STATUS_TRACKABLE.value?(status.to_s)

        ::Experiment.transaction do
          exp.update!(native_attrs) if native_attrs.any?
          Scinote::ElnUi::ExperimentProfile.upsert_for!(exp, profile_attrs) if profile_attrs.any?
        end

        render json: Scinote::ElnUi::ExpDetailPayload.call(
          exp, current_user,
          can_create_task: can_create_task?,
          can_manage_experiment: can_manage_experiment?
        )
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      private

      # 可读性沿用原生 PermissionCheckableModel#readable_by_user（与列表页同口径，
      # access_control D8「同源同层」）：这里再判一遍就是第二套口径。
      def experiment
        @experiment ||= Experiment.readable_by_user(current_user).find_by(id: params[:id])
        # 找不到就走原生那套 404/403 语义（不自己 render 一个「无权限」页，
        # 免得和原生行为分叉）。
        @experiment || raise(ActiveRecord::RecordNotFound)
      end

      def payload
        Scinote::ElnUi::ExpDetailPayload.call(
          @experiment,
          current_user,
          can_create_task: can_create_task?,
          can_manage_experiment: can_manage_experiment?
        )
      end

      # 状态有效性判定复用 ExpDetailPayload::STATUS_TRACKABLE 的 values（display→trackable
      # 单一来源），不再维护一份镜像的 TRACKABLE_STATUS，避免两份手工同步的映射漂移。
      def experiment_params
        # owner_user_id 空串 → 清显式负责人（回落指派/创建者推导）；其余 compact 后落库。
        params.expect(experiment: [:name, :due_date, :business_code, :owner_user_id, :purpose, :method, :status])
      end

      # ------------------------------------------------------------
      # 「在实验里新建任务」（SCN-EXP-DETAIL-5：项目负责人 / 小组组长可新建）
      #
      # 判定直接用原生权限位本体 —— 与列表页 can_create_project? 同一条理由：
      # Canaid 生成的 helper 在 User 实例上 respond_to? 不一定有，走判定本体最稳。
      # ------------------------------------------------------------
      def can_create_task?
        @experiment.permission_granted?(current_user, ExperimentPermissions::TASKS_CREATE)
      end

      # 实验级管理权限：本页用它近似 DEC-001 的「项目负责人 / 小组组长」准入
      # （原生没有 DOE 模块，也就没有对应权限位；近似映射已记 OPEN-4）。
      def can_manage_experiment?
        @experiment.permission_granted?(current_user, ExperimentPermissions::MANAGE)
      end
    end
  end
end
