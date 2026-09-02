# frozen_string_literal: true

require 'rails_helper'

# Scinote::Esignatures.enabled? 接入 AddonSetting 契约：
# 未写入设置行时按"已挂载即默认启用"。
RSpec.describe Scinote::Esignatures do
  describe '.enabled?' do
    it 'is true by default (no setting row => mounted addon on)' do
      expect(described_class.enabled?).to be true
    end

    it 'is false when the addon setting is disabled' do
      AddonSetting.create!(name: 'esignatures', enabled: false, configuration: {})
      expect(described_class.enabled?).to be false
    end
  end
end
