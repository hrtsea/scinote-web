# frozen_string_literal: true

# Per-addon instance-level configuration: enable flag + arbitrary JSON config.
# Addons that honor the `enabled?` contract read this table to decide whether
# their features are active. Mounted addons are ON by default (opt-out): when no
# row exists for a name, #enabled? returns true.
#
# Owned by the addon_settings engine (lives here, not in the host app/). As the
# management UI + discovery registry for every other addon, addon_settings
# declares `toggleable? => false` and must stay enabled — it is infrastructure,
# not an opt-out plugin, so it should not be removed from the Gemfile in
# production even though doing so is boot-safe (its routes simply 404).
class AddonSetting < ApplicationRecord
  class InvalidConfiguration < StandardError; end

  validates :name, presence: true, uniqueness: true

  validate :schema_integers_non_negative

  # An addon is enabled when no setting row exists (mounted = on by default),
  # or when its row explicitly sets `enabled` to true. Non-toggleable addons
  # (declared via `self.toggleable?` returning false, e.g. addon_settings, i18n)
  # are ALWAYS enabled — their flag is never user-controllable, at any layer.
  def self.enabled?(name)
    return true unless toggleable?(name)

    record = find_by(name: name)
    record.nil? ? true : record.enabled
  end

  # Whether an instance admin may toggle the addon's enable flag.
  # Convention: an addon module may declare `self.toggleable?`; when omitted the
  # addon is toggleable (true) by default. Core addons such as addon_settings and
  # i18n declare `toggleable?` returning false so they can never be turned off.
  def self.toggleable?(name)
    mod = addon_module(name)
    return true unless mod&.respond_to?(:toggleable?)

    mod.toggleable?
  end

  def self.for(name)
    find_or_initialize_by(name: name)
  end

  # Persist the enabled flag and (optionally) the configuration hash for an addon.
  # Note: `if configuration.present?` means passing `configuration: {}` is silently
  # ignored (existing config preserved) — callers can't reset to empty this way.
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
  # 约定：addon 在其模块上定义 self.config_schema 返回字段数组；未声明或模块
  # 不可达时返回 []，设置页据此仅渲染启用开关。字段形状：
  #   key:         存储键（字符串）
  #   type:        'boolean' | 'secret' | 'integer' | 'text' | 'select'
  #   label:       i18n 键（控件标题）
  #   help:        i18n 键（可选，帮助文本）
  #   default:     未设值时的回退值（可选）
  #   placeholder / options: 控件提示 / 下拉选项（可选）
  def self.config_schema_for(name)
    mod = addon_module(name)
    return [] unless mod&.respond_to?(:config_schema)

    mod.config_schema || []
  end

  # 索引卡片简介（参照 Label printers 的标题+描述风格）。
  # 约定：addon 模块定义 self.description 返回 i18n 键；未声明时返回 nil，
  # 索引卡片据此仅显示插件名（优雅降级）。
  def self.description_for(name)
    mod = addon_module(name)
    return nil unless mod&.respond_to?(:description)

    mod.description
  end

  # 配置子页的详细说明 i18n 键；未声明时返回 nil（子页不渲染说明块）。
  def self.detailed_help_for(name)
    mod = addon_module(name)
    return nil unless mod&.respond_to?(:detailed_help)

    mod.detailed_help
  end

  # 把表单提交的 configuration 转换为类型化 Hash 存入 JSONB（领域逻辑下沉到模型）。
  # 兼容旧契约：仍接受裸 JSON 字符串（整体原样存储）。
  # 新契约：表单按 schema 字段提交 configuration[key]=value，据字段类型转换。
  # 合并基线：raw 为 nil 或字段未提交时保留 existing 中的旧值，绝不静默清空
  # （boolean 未勾选即 false；secret 留空保留原密钥的逻辑见 coerce_config_value）。
  # 非法输入（JSON 解析失败 / integer 负值）抛出 JSON::ParserError / InvalidConfiguration，
  # 由上游控制器捕获并回退到错误提示。
  def self.typed_configuration(raw, name, existing: {})
    return existing if raw.nil?

    return JSON.parse(raw) if raw.is_a?(String)

    raw_hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
    schema = config_schema_for(name)
    config = existing || {}

    schema.each do |field|
      key = field[:key].to_s
      type = field[:type].to_s

      if type == 'boolean'
        # 未勾选时表单不提交该键，按 false 处理（可关闭）。
        config[key] = ActiveModel::Type::Boolean.new.cast(raw_hash[key])
      else
        next unless raw_hash.key?(key)

        config[key] = coerce_config_value(type, raw_hash[key], config[key])
      end
    end

    validate_typed_configuration!(schema, config)

    config
  end

  private

  # 解析某 addon 自描述模块 Scinote::<Name>；不可达（未挂载/命名不符）时返回 nil。
  # 约定式自描述（config_schema / description / detailed_help / toggleable?）统一从此取，
  # 避免在多个 reader 里重复 safe_constantize。
  def self.addon_module(name)
    "Scinote::#{name.to_s.camelize}".safe_constantize
  end

  # schema 字段类型转换（integer / secret / 默认字符串）。
  # secret 提交为空串时回退到 existing（保留已存密钥，不回显、不覆盖）。
  def self.coerce_config_value(type, value, existing)
    case type
    when 'integer'
      value.present? ? value.to_i : nil
    when 'secret'
      (value.presence || existing)
    else
      value.to_s
    end
  end

  # schema 声明的 integer 字段不接受负值。返回所有非法（负值）字段的 key，
  # 供“抛错”（控制器写入路径）与“加校验错误”（模型校验）两处共用，避免规则重复。
  def self.negative_integer_keys(schema, config)
    schema.filter_map do |field|
      next unless field[:type].to_s == 'integer'

      key = field[:key].to_s
      config[key].is_a?(Integer) && config[key].negative? ? key : nil
    end
  end

  # integer 负值属非法输入，由上游控制器捕获并回退到错误提示。
  def self.validate_typed_configuration!(schema, config)
    bad = negative_integer_keys(schema, config)
    raise InvalidConfiguration, "Invalid value for #{bad.join(', ')}: must be >= 0" if bad.any?
  end

  # schema 声明的 integer 字段不接受负值（必填/类型由 schema 约束）。
  # 直接赋值 configuration（如 update_for）不经 typed_configuration 时，
  # 由本校验兜底阻止负值写入；其它校验交给 schema 与上游白名单。
  def schema_integers_non_negative
    return if configuration.nil?

    schema = AddonSetting.config_schema_for(name)
    return if schema.blank?

    self.class.send(:negative_integer_keys, schema, configuration).each do |key|
      errors.add(:configuration, "#{key} must be >= 0")
    end
  end
end
