# frozen_string_literal: true

# ELN UI —— 项目审批人配置端点（REQ-RES-APPROVER · ADR-0029）
#
#   GET    /eln_project_approvers?project_id=xx   面板数据（该项目两阶段名单 + 候选）
#   POST   /eln_project_approvers                 增配一个人（project_id + stage + user_id）
#   DELETE /eln_project_approvers/:id             移除一个人
#   POST   /eln_project_approvers/init            一键初始化（把项目负责人写进两阶段名单）
#
# 权限口径一律问 ResourceApprovalPolicy.can_configure?（= 项目负责人，
# 不给团队/单位管理员开万能位 —— 见 Q5-2）。controller 自己不判第二遍。
#
# ⚠ 「一键初始化」是 fail-closed 的**冷启动出口**：新项目或换负责人之后名单是空的，
#   单据会一直卡在待审。没有它，用户得先理解整套概念才能用起来；
#   它也**不是**自动兜底 —— 不按按钮，挡住就是挡住。
#
# ⚠ ConfigError 一个类型收口所有「业务性拒绝」：阶段不合法、人不在团队、项目无权等。
#   散在各处自己 render 一次，yam下一次就得猜返回体有什么不同。
#
# ⚠ CSRF 不 skip：调用方（资源申请页签面板）显式带 X-CSRF-Token。
module Scinote
  module ElnUi
    class ProjectApproversController < ApplicationController
      class ConfigError < StandardError; end

      before_action :require_login
      before_action :check_team_membership

      def index
        render json: payload_for(params[:project_id])
      end

      def create
        project = load_managed_project!(params[:project_id])
        user = load_team_user!(params[:user_id])
        stage = normalize_stage!(params[:stage])

        approver = Scinote::ElnUi::ProjectApprover.add!(
          project: project, user: user, stage: stage, created_by: current_user
        )
        render json: { ok: true, id: approver.id, stage: approver.stage,
                       stageLabel: approver.stage_label,
                       payload: payload_for(project.id) }
      rescue ConfigError => e
        render_config_error(e)
      end

      def destroy
        approver = Scinote::ElnUi::ProjectApprover.find_by(id: params[:id])
        raise ConfigError, '配置不存在' if approver.nil?

        project = approver.project
        check_configurable!(project)
        approver.destroy!
        render json: { ok: true, payload: payload_for(project.id) }
      rescue ConfigError => e
        render_config_error(e)
      end

      # 一键初始化：把当前项目负责人写进**审批**两阶段名单（幂等，已存在的不重复写）
      #
      # ⚠ **刻意不写 `receipt`（验货）阶段** —— ADR-0032 把验货人定为**独立可配**的第三阶段，
      #   「谁批采购」与「谁验货到货」是两种职责。若这里顺手把负责人也塞进验货名单，
      #   等于用一次快捷操作静默决定了「谁来验别人的货」——
      #   而且它会连带触发自验问题（负责人往往是申请人）。宁可让该阶段空着：
      #   warnings 会明写「未配置验货人」，用户看得见缺什么。
      def init
        project = load_managed_project!(params[:project_id])
        owners = Scinote::ElnUi::ResourceApprovalPolicy.project_owners(project)
        raise ConfigError, '该项目没有负责人，无法初始化' if owners.empty?

        stages = Scinote::ElnUi::ProjectApprover.stages - %w[receipt]
        before_count = Scinote::ElnUi::ProjectApprover.for_project(project).count
        stages.each do |stage|
          owners.each do |owner|
            Scinote::ElnUi::ProjectApprover.add!(
              project: project, user: owner, stage: stage, created_by: current_user
            )
          end
        end
        added = Scinote::ElnUi::ProjectApprover.for_project(project).count - before_count

        render json: { ok: true, added: added, owners: owners.size, stages: stages,
                       skippedStages: %w[receipt],
                       payload: payload_for(project.id) }
      rescue ConfigError => e
        render_config_error(e)
      end

      # 到货验收的项目级策略：允不允许验货人验自己的申请单（D3 · ADR-0032）。
      #
      # ⚠ 为什么独立成一个端点而不是并进 create/destroy：名单是**谁**、策略是**能不能**，
      #   两者增删频率与语义都不同；混在一个端点里迟早长出 `type=xxx` 的分叉参数。
      # ⚠ 只有「写」端点，**没有**单独的读端点：策略随 panel payload 的 receiptPolicy 键
      #   一起下发（前端配置面板一次请求拿全名单 + 开关），再开一个 GET 只会制造
      #   「两次读可能读到不同值」的窗口。
      def update_receipt_policy
        project = load_managed_project!(params[:project_id])
        # ⚠ 只认明确的布尔语义：Rails 的 "0"/"false" 会被 truthy 化，
        #   而 checkbox 取消勾选恰好提交 "0" —— 直接 !!params 会把「关」存成「开」。
        value = ActiveModel::Type::Boolean.new.cast(params[:allow_self_verification])
        raise ConfigError, '参数 allow_self_verification 必须是 true/false' if value.nil?

        Scinote::ElnUi::ReceiptPolicy.set_allow_self_verification!(
          project: project, value: value, updated_by: current_user
        )
        render json: { ok: true, projectId: project.id, allowSelfVerification: value,
                       payload: payload_for(project.id) }
      rescue ConfigError => e
        render_config_error(e)
      end

      private

      def payload_for(project_id)
        Scinote::ElnUi::ProjectApproversPayload.call(
          user: current_user, team: current_team, project_id: project_id
        )
      end

      # 收口 ConfigError → HTTP 状态：授权失败(无权配置)一律 403，
      # 业务错误(阶段非法/人不在团队/项目不存在等)才 422。三处 rescue 共用，口径一致。
      def render_config_error(e)
        status = e.message == '无权配置该项目审批人' ? :forbidden : :unprocessable_entity
        render json: { ok: false, error: e.message }, status: status
      end

      def load_managed_project!(project_id)
        project = ::Project.find_by(id: project_id)
        raise ConfigError, '项目不存在' if project.nil?

        check_configurable!(project)
        project
      end

      def check_configurable!(project)
        return if Scinote::ElnUi::ResourceApprovalPolicy
                    .can_configure?(current_user, project, current_team)

        raise ConfigError, '无权配置该项目审批人'
      end

      def load_team_user!(user_id)
        user = ::User.find_by(id: user_id)
        raise ConfigError, '用户不存在' if user.nil?
        # 审批人必须是本团队成员 —— 配一个团队外的人进来，他在列表里取不到任何东西，
        # 只会让「为什么没人批」变得最难理解。
        raise ConfigError, '该用户不属于当前团队' unless user.teams.exists?(id: current_team.id)

        user
      end

      def normalize_stage!(stage)
        stage = stage.to_s
        unless Scinote::ElnUi::ProjectApprover.stages.include?(stage)
          # ⚠ 报错文案必须由**白名单本身**生成，不能手写「group 或 project」——
          #   2026-10-06 加 receipt 阶段后旧文案会把合法值说成非法（已实测踩过）。
          labels = Scinote::ElnUi::ProjectApprover.stages.map do |s|
            "#{s}（#{Scinote::ElnUi::ProjectApprover.stage_labels[s] || s}）"
          end
          raise ConfigError, "阶段必须为 #{labels.join(' / ')} 之一"
        end

        stage
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
