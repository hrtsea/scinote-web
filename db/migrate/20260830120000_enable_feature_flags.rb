# frozen_string_literal: true

# 开启仓库/库存高级能力、协议/化学结构、表单/存储位置/用户组等默认关闭的功能开关。
# 这些开关均由 ApplicationSettings.instance.values['<key>'] 控制，且 DB 记录默认空 -> 全关。
# 注意：
#   - protocols_io_enabled? 还需 ENV['PROTOCOLS_IO_ACCESS_TOKEN']（真实 API 令牌）
#   - ai_parser_enabled? 还需 ENV['AI_PROTOCOLS_PARSER']（AI 协议解析服务地址）
class EnableFeatureFlags < ActiveRecord::Migration[7.2]
  KEYS = %w[
    stock_management_enabled
    repository_row_connections_enabled
    equipment_booking_enabled
    forms_enabled
    storage_locations_enabled
    user_groups_enabled
    protocol_content_locking_enabled
    ai_protocol_parser_enabled
  ].freeze

  def up
    settings = ApplicationSettings.first || ApplicationSettings.new
    merged = (settings.values || {}).merge(KEYS.index_with { true })
    # Settings 模型的 before_validation 会执行 self.values = merged_values || values，
    # 而 merged_values 在读取 values 时已被缓存（含 env 合并）。必须同步设置 merged_values，
    # 否则空缓存 {} 会覆盖本次写入，导致开关未真正生效。
    settings.merged_values = merged
    settings.values = merged
    settings.save!
  end

  def down
    settings = ApplicationSettings.first
    return unless settings && settings.values.present?

    removed = (settings.values || {}).except(*KEYS)
    settings.merged_values = removed
    settings.values = removed
    # 若移除后为空，则删除该记录，避免残留空行
    if removed.empty?
      settings.destroy!
    else
      settings.save!
    end
  end
end
