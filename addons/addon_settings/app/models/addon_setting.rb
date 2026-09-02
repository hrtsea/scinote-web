# frozen_string_literal: true

# Per-addon instance-level configuration: enable flag + arbitrary JSON config.
# Addons that honor the `enabled?` contract read this table to decide whether
# their features are active. Mounted addons are ON by default (opt-out): when no
# row exists for a name, #enabled? returns true.
#
# Owned by the addon_settings engine (lives here, not in the host app/, so the
# addon stays self-contained and removable via the Gemfile alone).
class AddonSetting < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  validate :schema_integers_non_negative

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

  # 索引卡片简介（参照 Label printers 的标题+描述风格）。
  # 约定：addon 模块定义 self.description 返回 i18n 键；未声明时返回 nil，
  # 索引卡片据此仅显示插件名（优雅降级）。
  def self.description_for(name)
    mod = "Scinote::#{name.to_s.camelize}".safe_constantize
    return nil unless mod&.respond_to?(:description)

    mod.description
  end

  # 配置子页的详细说明 i18n 键；未声明时返回 nil（子页不渲染说明块）。
  def self.detailed_help_for(name)
    mod = "Scinote::#{name.to_s.camelize}".safe_constantize
    return nil unless mod&.respond_to?(:detailed_help)

    mod.detailed_help
  end

  private

  # schema 声明的 integer 字段不接受负值（必填/类型由 schema 约束）。
  # 负值属非法输入，阻止写入；其它校验交给 schema 与上游白名单。
  def schema_integers_non_negative
    return if configuration.nil?

    schema = AddonSetting.config_schema_for(name)
    return if schema.blank?

    schema.each do |field|
      next unless field[:type].to_s == 'integer'

      value = configuration[field[:key].to_s]
      next unless value.is_a?(Integer)

      errors.add(:configuration, "#{field[:key]} must be >= 0") if value.negative?
    end
  end
end
