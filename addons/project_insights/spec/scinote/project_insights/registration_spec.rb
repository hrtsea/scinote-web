# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::ProjectInsights do
  describe '.enabled?' do
    it 'is true by default (no setting row => mounted addon on)' do
      expect(described_class.enabled?).to be true
    end

    it 'is false when the addon setting is disabled' do
      AddonSetting.create!(name: 'project_insights', enabled: false, configuration: {})
      expect(described_class.enabled?).to be false
    end

    it 'is true when the addon setting is explicitly enabled' do
      AddonSetting.create!(name: 'project_insights', enabled: true, configuration: {})
      expect(described_class.enabled?).to be true
    end
  end

  # 注：P1 的 dashboard widget 注册已撤销（addon 改为独立 /insights 页面），
  # 故不再有 register_widgets! 方法可测；相关契约转移到 insights 页面 spec。
end
