# frozen_string_literal: true

# Per-addon instance-level configuration: enable flag + arbitrary JSON config.
# Addons that honor the `enabled?` contract read this table to decide whether
# their features are active. Mounted addons are ON by default (opt-out): when no
# row exists for a name, #enabled? returns true.
class AddonSetting < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  # An addon is enabled when no setting row exists (mounted = on by default),
  # or when its row explicitly sets `enabled` to true.
  def self.enabled?(name)
    record = find_by(name: name)
    record.nil? ? true : record.enabled
  end

  def self.for(name)
    find_or_initialize_by(name: name)
  end

  # Persist the enabled flag and (optionally) the configuration hash for an addon.
  def self.update_for(name, enabled:, configuration: nil)
    setting = find_or_initialize_by(name: name)
    setting.enabled = enabled
    setting.configuration = configuration if configuration.present?
    setting.save!
    setting
  end

  def config_value(key)
    configuration&.fetch(key.to_s, nil)
  end

  # 读取某 addon 自声明的配置 schema（供设置页动态渲染表单）。
  # 约定：addon 在其模块上定义 self.config_schema 返回字段数组；
  # 未声明或模块不可达时返回 []，设置页据此仅渲染启用开关。
  def self.config_schema_for(name)
    mod = "Scinote::#{name.to_s.camelize}".safe_constantize
    return [] unless mod&.respond_to?(:config_schema)

    mod.config_schema || []
  end
end
