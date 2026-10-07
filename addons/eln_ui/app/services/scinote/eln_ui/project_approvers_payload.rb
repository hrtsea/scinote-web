# frozen_string_literal: true

# ELN UI —— 项目审批人配置面板的数据装配（REQ-RES-APPROVER · ADR-0029 Q6-1）
#
# 面板挂「资源中心 → 资源申请」页签内（DEC-012：自研能力挂页面内面板，不新造外壳）。
# 按项目下拉切换 —— 一个负责人可能管多个项目，名单是**逐项目**的。
#
# ⚠ 出去的每一个布尔位都必须与 ResourceApprovalPolicy 同源：
#   面板说「能配」而后端说「不能」= 按钮可用、点下去 422 ——
#   脚手架负责显示、闸门负责放行，两者为同一句话负责，不能各说各的。
module Scinote
  module ElnUi
    class ProjectApproversPayload
      class << self
        def call(user:, team:, project_id: nil)
          new(user: user, team: team, project_id: project_id).call
        end
      end

      def initialize(user:, team:, project_id: nil)
        @user = user
        @team = team
        @project_id = project_id
      end

      def call
        projects = ResourceApprovalPolicy.configurable_projects(@user, @team)
        return empty_payload(projects) if projects.empty?

        project = pick_project(projects)
        return empty_payload(projects) if project.nil?

        {
          projects: projects.map { |p| { id: p.id, name: p.name.to_s } },
          project: project_block(project),
          stages: stages_block(project),
          candidates: ResourceApprovalPolicy.candidates(project, @team).map { |u| candidate_row(u) },
          # ⚠ 与名单**同一次**下发：前端配置面板不该为「验货人名单」和「能不能自验」
          #   发两个请求 —— 两个请求就可能出现「名单是新的、开关是旧的」这种撕裂显示。
          receiptPolicy: receipt_policy_block(project),
          # fail-closed 的后果必须写在页面上：不配置的阶段没人能批，
          # 光给一个不动的按钮，用户只会以为系统坏了。
          warnings: warnings_block(project)
        }
      end

      private

      def empty_payload(projects)
        {
          projects: projects.map { |p| { id: p.id, name: p.name.to_s } },
          project: nil,
          stages: {},
          candidates: [],
          receiptPolicy: nil,
          warnings: projects.empty? ? ['您不是任何项目的负责人，无法配置审批人'] : ['请选择项目']
        }
      end

      def pick_project(projects)
        return projects.first if @project_id.blank?

        projects.find { |p| p.id.to_s == @project_id.to_s }
      end

      def project_block(project)
        { id: project.id, name: project.name.to_s }
      end

      # ⚠ stages 的 users 必须带**审批人行 id**（= DELETE /eln_project_approvers/:id 的 :id），
      #   否则前端「移除」按钮拿不到正确的行、只能拿到 user id（删不掉）。
      #   candidates 仍用 candidate_row（user id），两者别混。
      def stages_block(project)
        Scinote::ElnUi::ProjectApprover.stages.each_with_object({}) do |stage, acc|
          approvers = Scinote::ElnUi::ProjectApprover.for_project(project).for_stage(stage).to_a
          acc[stage] = {
            label: Scinote::ElnUi::ProjectApprover.stage_labels[stage] || stage,
            configured: approvers.any?,
            users: approvers.map { |ap| user_row(ap) }
          }
        end
      end

      def warnings_block(project)
        ResourceApprovalPolicy.unconfigured_stages(project).map do |stage|
          label = Scinote::ElnUi::ProjectApprover.stage_labels[stage] || stage
          "未配置#{label}人：处于「#{label}」阶段的资源申请将无人可批，单据会一直卡在该阶段。"
        end
      end

      # persisted=false ⇒ 该项目还没落过策略行，当前显示的是**默认拒绝自验**。
      #   前端要能说出「现在用的是默认值」而不是假装这是显式配置。
      def receipt_policy_block(project)
        policy = Scinote::ElnUi::ReceiptPolicy.for_project(project)
        { allowSelfVerification: policy.allow_self_verification?,
          persisted: policy.persisted? }
      end

      def candidate_row(u)
        { id: u.id, name: (u.full_name.presence || u.email).to_s }
      end

      # approver 行 → 前端要两样东西：
      #   · id        = 审批人**行** id（DELETE 端点要它）
      #   · user_id   = 用户 id（仅供展示/对照）
      def user_row(approver)
        user = approver.user
        { id: approver.id, user_id: approver.user_id,
          name: (user&.full_name.presence || user&.email).to_s }
      end
    end
  end
end
