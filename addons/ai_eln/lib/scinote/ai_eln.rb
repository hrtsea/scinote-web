# frozen_string_literal: true

require "scinote/ai_eln/version"
require "scinote/ai_eln/configuration"
require "scinote/ai_eln/engine"

module Scinote
  module AiEln
    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      # 全局开关：false 时整个插件退化原生 SciNote（规格 §7 enable / §3.3 兼容性）
      def enabled?
        configuration.enable
      end
    end
  end
end
