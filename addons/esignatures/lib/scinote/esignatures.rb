# frozen_string_literal: true

module Scinote
  module Esignatures
    # 门控：本 addon 是否在实例级别启用（接入 AddonSetting 契约）。
    # 未写入设置行时按"已挂载即默认启用"。
    def self.enabled?
      AddonSetting.enabled?('esignatures')
    end

    # 声明本 addon 在"设置 → Addons"页所需的配置项（暴露给管理员填写）。
    def self.config_schema
      [
        {
          key: 'require_intent',
          type: 'boolean',
          label: 'esignatures.settings.config.require_intent',
          help: 'esignatures.settings.config.require_intent_help',
          default: true
        }
      ].freeze
    end

    # 读取本 addon 的某项实例级配置（来自 addon_settings.configuration）。
    def self.config_value(key)
      AddonSetting.for('esignatures').config_value(key)
    end

    # 是否强制要求签名者填写"签名意图"。默认 true（未配置时亦为 true）。
    def self.require_intent?
      config_value('require_intent') != false
    end
  end
end
