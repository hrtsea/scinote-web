# frozen_string_literal: true

module Scinote
  module AiEln
    # 单功能 AI 端点聚合控制器（规格 §2 各 AI-xxx）
    # 全部经 Canaid `ai:use` 权限守卫（宿主注入 can_*_experiment_proc）
    class AiActionsController < ApplicationController
      include HostModels

      before_action :ensure_enabled
      before_action :authorize_experiment, only: %i[summarize root_cause]

      def summarize
        # TODO(issue-05): 调用 LlmAdapter 生成实验小结，落 ai_sessions/interactions
        head :not_implemented
      end

      def root_cause
        # TODO(issue-05): 失败现象根因分析
        head :not_implemented
      end

      def parse_recipe
        # TODO(issue-07): 非结构化文本解析配方
        head :not_implemented
      end

      def parse_attachment
        # TODO(issue-06): PDF / 图片 OCR / CSV 解析
        head :not_implemented
      end

      def semantic_search
        # TODO(issue-08): 混合检索（pgvector + tsvector）
        head :not_implemented
      end

      private

      def ensure_enabled
        head :forbidden unless Scinote::AiEln.enabled?
      end

      def authorize_experiment
        exp = experiment_class.find_by(id: params[:experiment_id])
        head :forbidden unless exp && can_read_experiment?(current_user, exp)
      end
    end
  end
end
