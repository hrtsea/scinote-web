# frozen_string_literal: true

# 本地复刻专用：绕开 Protocol.ai_parser_enabled? 的 ENV / ApplicationSettings /
# AddonSetting 三重门控，使 addon 在役时直接放行。
#
# ⚠ 仅用于本地复刻验证。生产部署应删除本装饰器并正确配置
#    ENV['AI_PROTOCOLS_PARSER'] + ApplicationSettings['ai_protocol_parser_enabled']
#    + AddonSetting.enabled?('ai_protocols')。
module Scinote
  module AiProtocols
    module ProtocolAiParserDecorator
      def self.prepended(base)
        base.singleton_class.prepend(
          Module.new do
            def ai_parser_enabled?
              true
            end
          end
        )
      end
    end
  end
end

Protocol.prepend(Scinote::AiProtocols::ProtocolAiParserDecorator) if defined?(Protocol)
