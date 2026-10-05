# frozen_string_literal: true

module Scinote
  module AiEln
    # 单功能 AI 端点聚合控制器（规格 §2 各 AI-xxx）
    # 全部经 Canaid `ai:use` 权限守卫（宿主注入 can_*_proc）
    class AiActionsController < ApplicationController
      include HostModels

      before_action :ensure_enabled
      before_action :ensure_user
      before_action :authorize_experiment, only: %i[summarize root_cause]
      before_action :authorize_protocol,   only: %i[parse_recipe]
      before_action :authorize_asset,      only: %i[parse_attachment]

      def summarize
        experiment = experiment_class.find_by(id: params[:experiment_id])
        agent = Scinote::AiEln::SciNoteAssistantAgent.with(experiment:, current_user:)
        result = agent.summarize_experiment.generate_now
        # D-persist=B：审计/追踪委托 ActiveAgent actionagent 面板，不写 ai_eln_ai_interactions/audit_logs
        render json: { summary: result.message }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def root_cause
        # TODO(issue-05): 失败现象根因分析
        head :not_implemented
      end

      def parse_recipe
        protocol = protocol_class.find_by(id: params[:protocol_id])
        agent = Scinote::AiEln::SciNoteAssistantAgent.with(protocol:, current_user:)
        result = agent.parse_recipe.generate_now
        render json: { result: result.message }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def parse_attachment
        asset = asset_class.find_by(id: params[:asset_id])
        agent = Scinote::AiEln::SciNoteAssistantAgent.with(asset:, current_user:)
        result = agent.parse_attachment.generate_now
        render json: { result: result.message }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def semantic_search
        agent = Scinote::AiEln::SciNoteAssistantAgent.with(query: params[:query].to_s, current_user:)
        result = agent.semantic_search.generate_now
        render json: { result: result.message }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def ensure_enabled
        head :forbidden unless Scinote::AiEln.enabled?
      end

      def ensure_user
        head :forbidden unless current_user
      end

      def authorize_experiment
        exp = experiment_class.find_by(id: params[:experiment_id])
        head :forbidden unless exp && can_read_experiment?(current_user, exp)
      end

      def authorize_protocol
        proto = protocol_class.find_by(id: params[:protocol_id])
        head :forbidden unless proto && can_read_protocol?(current_user, proto)
      end

      def authorize_asset
        asset = asset_class.find_by(id: params[:asset_id])
        head :forbidden unless asset && can_read_asset?(current_user, asset)
      end
    end
  end
end
