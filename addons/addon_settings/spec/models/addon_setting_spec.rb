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

    it 'always returns true for a non-toggleable addon, even if its row is disabled' do
      stub_const('Scinote::TempLockedAddon', Module.new do
        def self.toggleable?
          false
        end
      end)
      AddonSetting.create!(name: 'temp_locked_addon', enabled: false, configuration: {})
      expect(AddonSetting.enabled?('temp_locked_addon')).to be true
    end
  end

  describe '.for' do
    it 'finds or initializes by name' do
      setting = AddonSetting.for('project_insights')
      expect(setting.name).to eq 'project_insights'
      expect(setting).to be_new_record
    end
  end

  describe '.toggleable?' do
    it 'returns true when the addon module does not declare toggleable?' do
      stub_const('Scinote::TempPlainAddon', Module.new)
      expect(AddonSetting.toggleable?('temp_plain_addon')).to be true
    end

    it 'returns false when the addon module declares toggleable? false' do
      stub_const('Scinote::TempLockedAddon', Module.new do
        def self.toggleable?
          false
        end
      end)
      expect(AddonSetting.toggleable?('temp_locked_addon')).to be false
    end

    it 'returns true when the addon module declares toggleable? true' do
      stub_const('Scinote::TempFreeAddon', Module.new do
        def self.toggleable?
          true
        end
      end)
      expect(AddonSetting.toggleable?('temp_free_addon')).to be true
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

    # 模型层数据保全契约：未传 configuration: 时绝不抹掉已存配置。
    # 控制器开启/禁用切换依赖此不变式（typed_configuration 在 raw 为 nil 时
    # 保留 setting.configuration）；若 update_for 改为无条件覆盖，会静默清空密钥等配置。
    it 'preserves the existing configuration when configuration is omitted' do
      AddonSetting.update_for('esignatures', enabled: true,
                              configuration: { 'require_meaning' => true })
      AddonSetting.update_for('esignatures', enabled: false)

      expect(AddonSetting.for('esignatures').configuration).to eq({ 'require_meaning' => true })
    end
  end

  describe '.config_schema_for' do
    it 'returns [] when the addon module cannot be resolved' do
      expect(AddonSetting.config_schema_for('no_such_addon_xyz')).to eq([])
    end

    it 'returns [] when the resolved module does not declare a schema' do
      stub_const('Scinote::TempNoSchemaAddon', Module.new)
      expect(AddonSetting.config_schema_for('temp_no_schema_addon')).to eq([])
    end

    it 'returns the schema declared on the addon module' do
      stub_const('Scinote::TempSchemaAddon', Module.new do
        def self.config_schema
          [{ key: 'api_key', type: 'secret', label: 'API key' }]
        end
      end)

      expect(AddonSetting.config_schema_for('temp_schema_addon')).to eq(
        [{ key: 'api_key', type: 'secret', label: 'API key' }]
      )
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

  describe '.description_for' do
    it 'returns nil when the addon module cannot be resolved' do
      expect(AddonSetting.description_for('no_such_addon_xyz')).to be_nil
    end

    it 'returns nil when the resolved module does not declare a description' do
      stub_const('Scinote::TempNoDescAddon', Module.new)
      expect(AddonSetting.description_for('temp_no_desc_addon')).to be_nil
    end

    it 'returns the description key declared on the addon module' do
      stub_const('Scinote::TempDescAddon', Module.new do
        def self.description
          'temp_desc_addon.addon.description'
        end
      end)

      expect(AddonSetting.description_for('temp_desc_addon')).to eq('temp_desc_addon.addon.description')
    end
  end

  describe '.detailed_help_for' do
    it 'returns nil when the addon module cannot be resolved' do
      expect(AddonSetting.detailed_help_for('no_such_addon_xyz')).to be_nil
    end

    it 'returns the detailed_help key declared on the addon module' do
      stub_const('Scinote::TempHelpAddon', Module.new do
        def self.detailed_help
          'temp_help_addon.addon.detailed_help'
        end
      end)

      expect(AddonSetting.detailed_help_for('temp_help_addon')).to eq('temp_help_addon.addon.detailed_help')
    end
  end

  describe '.addon_module' do
    it 'resolves the Scinote::<Name> module when present' do
      stub_const('Scinote::TempResolveAddon', Module.new)
      expect(AddonSetting.send(:addon_module, 'temp_resolve_addon')).to eq(Scinote::TempResolveAddon)
    end

    it 'returns nil for an unresolvable addon' do
      expect(AddonSetting.send(:addon_module, 'no_such_addon_xyz')).to be_nil
    end
  end

  describe '.typed_configuration' do
    let(:schema_module) do
      stub_const('Scinote::TempCfgAddon', Module.new do
        def self.config_schema
          [
            { key: 'api_key', type: 'secret', label: 'API key' },
            { key: 'require_intent', type: 'boolean', label: 'Require intent' },
            { key: 'default_period_days', type: 'integer', label: 'Days' }
          ]
        end
      end)
    end

    it 'returns the existing config unchanged when raw is nil (preserves data)' do
      schema_module
      expect(AddonSetting.typed_configuration(nil, 'temp_cfg_addon', existing: { 'api_key' => 'x' }))
        .to eq({ 'api_key' => 'x' })
    end

    it 'parses a legacy JSON string wholesale' do
      schema_module
      expect(AddonSetting.typed_configuration('{"a":1}', 'temp_cfg_addon'))
        .to eq({ 'a' => 1 })
    end

    it 'casts boolean to false when unchecked and preserves a blank secret' do
      schema_module
      result = AddonSetting.typed_configuration(
        { 'api_key' => '', 'require_intent' => '0', 'default_period_days' => '30' },
        'temp_cfg_addon',
        existing: { 'api_key' => 'prev' }
      )
      expect(result['require_intent']).to be false
      expect(result['default_period_days']).to eq(30)
      expect(result['api_key']).to eq('prev')
    end

    it 'raises InvalidConfiguration on a negative integer' do
      schema_module
      expect do
        AddonSetting.typed_configuration({ 'default_period_days' => '-5' }, 'temp_cfg_addon')
      end.to raise_error(AddonSetting::InvalidConfiguration)
    end
  end
end
