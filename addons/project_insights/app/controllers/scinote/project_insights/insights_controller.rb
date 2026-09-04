# frozen_string_literal: true

module Scinote
  module ProjectInsights
    # 数据端点（Issue P3）：按 kind 返回对应聚合的 JSON。
    # 复用 P2 聚合服务；无需新权限，端点受 enabled? 隐式保护
    # （widget 仅在启用时渲染并发起请求）。
    class InsightsController < ApplicationController
      before_action :ensure_enabled

      # URL 的 kind 参数到聚合服务方法的映射：
      # status 对应 status_overview（其余同名）。
      KIND_TO_METHOD = {
        status: :status_overview,
        workload: :workload,
        bottlenecks: :bottlenecks,
        due_dates: :due_dates
      }.freeze

      # 支持「按档返回任务列表」的 kind（其余 kind 走聚合计数，无「档」概念）。
      TASKS_KINDS = %i(due_dates bottlenecks).freeze

      def index
        if params[:kind].present?
          method = KIND_TO_METHOD[params[:kind].to_s.to_sym]
          # 端点需要团队上下文（与 dashboard 一致）；无当前团队时拒绝，
          # 避免聚合对 MyModuleStatusFlow.where(team_id: nil) 查出空流、readable_by_user(user, nil) 行为未定义。
          unless method && current_team
            head(method ? :forbidden : :bad_request)
            return
          end

          # D 可交互成员多选：workload 支持 member_ids[] 过滤，其余 kind 忽略该参数。
          if method == :workload && params[:member_ids].present?
            render json: aggregator.workload(member_ids: Array(params[:member_ids]).map(&:to_i))
          else
            render json: aggregator.public_send(method)
          end
        else
          # 独立 Insights 页面（对齐产品 UI 截图）。widget 数据仍由各
          # kind 对应的 JSON 端点异步加载，保持 P2/P3 的数据通路不变。
          return head(:forbidden) unless current_team

          @project = current_project
          @projects = current_team.projects.where(archived: false)
          render :index
        end
      end

      # 按档返回任务列表（待补 G / Bottlenecks 分段选择器）：kind ∈ due_dates|bottlenecks，
      # bucket 为对应档名；复用 #tasks_for。受 enabled? 与 current_team 保护。
      def tasks
        kind = params[:kind].to_s.to_sym
        bucket = params[:bucket].to_s.to_sym
        unless TASKS_KINDS.include?(kind) && bucket.present? && current_team
          head :bad_request
          return
        end

        render json: aggregator.tasks_for(kind, bucket)
      end

      private

      def ensure_enabled
        head :forbidden unless Scinote::ProjectInsights.enabled?
      end

      def aggregator
        AggregatorService.new(current_user, current_team, current_project)
      end

      # 项目级过滤：project_id 必须属于当前团队；无效 id 触发 RecordNotFound -> 404。
      def current_project
        params[:project_id].present? ? current_team.projects.find(params[:project_id]) : nil
      end
    end
  end
end
