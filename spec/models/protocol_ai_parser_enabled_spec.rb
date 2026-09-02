# frozen_string_literal: true

require 'rails_helper'

# ai_parser_enabled? 现在叠加 AddonSetting 契约：即使外部解析服务已配置，
# 实例管理员在设置页关闭 ai_protocols 后，该开关也必须返回 false。
RSpec.describe Protocol, type: :model do
  describe '.ai_parser_enabled?' do
    around do |example|
      original = ENV.fetch('AI_PROTOCOLS_PARSER', nil)
      ENV['AI_PROTOCOLS_PARSER'] = 'http://parser.test'
      example.run
      if original.nil?
        ENV.delete('AI_PROTOCOLS_PARSER')
      else
        ENV['AI_PROTOCOLS_PARSER'] = original
      end
    end

    before do
      ApplicationSettings.instance.update(
        values: ApplicationSettings.instance.values.merge('ai_protocol_parser_enabled' => true)
      )
    end

    it 'is true when the addon setting is enabled (default, no row)' do
      expect(Protocol.ai_parser_enabled?).to be true
    end

    it 'is false when the addon setting is disabled' do
      AddonSetting.create!(name: 'ai_protocols', enabled: false, configuration: {})
      expect(Protocol.ai_parser_enabled?).to be false
    end
  end
end
