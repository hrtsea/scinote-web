# frozen_string_literal: true

module Scinote
  module AiEln
    # 宿主模型解析：所有引用经 configuration.xxx_class.constantize，
    # 满足 create-engine HARD-GATE #3（无硬编码宿主常量）、规格 §1.2-3 数据隔离
    module HostModels
      def experiment_class
        Scinote::AiEln.configuration.experiment_class.constantize
      end

      def protocol_class
        Scinote::AiEln.configuration.protocol_class.constantize
      end

      def report_class
        Scinote::AiEln.configuration.report_class.constantize
      end

      def recipe_class
        Scinote::AiEln.configuration.recipe_class.constantize
      end

      def user_class
        Scinote::AiEln.configuration.user_class.constantize
      end

      def asset_class
        Scinote::AiEln.configuration.asset_class.constantize
      end

      # 权限复用：转发宿主的 can_read/can_create 实现，不自行实现权限逻辑
      def can_read_experiment?(user, experiment)
        Scinote::AiEln.configuration.can_read_experiment_proc.call(user, experiment)
      end

      def can_create_experiment?(user, experiment)
        Scinote::AiEln.configuration.can_create_experiment_proc.call(user, experiment)
      end

      def can_read_protocol?(user, protocol)
        Scinote::AiEln.configuration.can_read_protocol_proc.call(user, protocol)
      end

      def can_read_asset?(user, asset)
        Scinote::AiEln.configuration.can_read_asset_proc.call(user, asset)
      end
    end
  end
end
