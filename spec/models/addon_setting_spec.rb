# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AddonSetting, type: :model do
  describe '.enabled?' do
    it 'returns true when no setting row exists (mounted addon on by default)' do
      expect(AddonSetting.enabled?('esignatures')).to be true
    end

    it 'returns false when the row is disabled' do
      AddonSetting.create!(name: 'esignatures', enabled: false, configuration: {})
      expect(AddonSetting.enabled?('esignatures')).to be false
    end

    it 'returns true when the row is enabled' do
      AddonSetting.create!(name: 'esignatures', enabled: true, configuration: {})
      expect(AddonSetting.enabled?('esignatures')).to be true
    end
  end

  describe '.for' do
    it 'finds or initializes by name' do
      setting = AddonSetting.for('project_insights')
      expect(setting.name).to eq 'project_insights'
      expect(setting).to be_new_record
    end
  end

  describe '.update_for' do
    it 'creates a row and persists enabled + configuration' do
      setting = AddonSetting.update_for(
        'esignatures', enabled: false, configuration: { 'require_meaning' => true }
      )
      expect(setting).to be_persisted
      expect(setting.enabled).to be false
      expect(setting.configuration).to eq({ 'require_meaning' => true })
      expect(AddonSetting.enabled?('esignatures')).to be false
    end

    it 'updates an existing row' do
      AddonSetting.create!(name: 'esignatures', enabled: true, configuration: {})
      AddonSetting.update_for('esignatures', enabled: false, configuration: {})
      expect(AddonSetting.enabled?('esignatures')).to be false
    end
  end

  describe '#config_value' do
    it 'reads a key from the configuration jsonb' do
      setting = AddonSetting.create!(
        name: 'esignatures', enabled: true, configuration: { 'require_meaning' => false }
      )
      expect(setting.config_value('require_meaning')).to be false
    end
  end

  describe 'validations' do
    it 'requires a unique name' do
      AddonSetting.create!(name: 'esignatures', enabled: true, configuration: {})
      duplicate = AddonSetting.new(name: 'esignatures', enabled: true, configuration: {})
      expect(duplicate).not_to be_valid
    end
  end
end
