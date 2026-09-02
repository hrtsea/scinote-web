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

      def index
        method = KIND_TO_METHOD[params[:kind].to_s.to_sym]
        # 端点需要团队上下文（与 dashboard 一致）；无当前团队时拒绝，
        # 避免聚合对 MyModuleStatusFlow.where(team_id: nil) 查出空流、readable_by_user(user, nil) 行为未定义。
        unless method && current_team
          head(method ? :forbidden : :bad_request)
          return
        end

        render json: aggregator.public_send(method)
      end

      private

      def ensure_enabled
        head :forbidden unless Scinote::ProjectInsights.enabled?
      end

      def aggregator
        AggregatorService.new(current_user, current_team)
      end
    end
  end
end
