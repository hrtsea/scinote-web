# frozen_string_literal: true

# 开启三个默认关闭的宿主功能开关：
#   - analytical_reporting_enabled   任务级分析报告（ReportTemplate）
#   - experiment_reporting_enabled?  实验级分析报告（AnalyticalReport）
#   - versioned_attachments_enabled  附件多版本历史（VersionedAttachments）
#
# 三者均由 ApplicationSettings.instance.values['<key>'] 控制，DB 记录默认空 -> 全关。
#
# 🔴 不要试图用 ENV 开这些开关：`ApplicationSettings#load_values_from_env` 做
#   `transform_keys(&:downcase)`，ENV['APP_STTG_ANALYTICAL_REPORTING_ENABLED'] 会变成
#   **带前缀**的 'app_sttg_analytical_reporting_enabled'，与消费点读的键名对不上；
#   且 ENV 值是字符串 "true"，而消费点写的是 `== true` 严格比较。双重失效，只能写 DB。
#
# 🔴 写入时必须同时设 merged_values：Settings 的 before_validation 执行
#   `self.values = merged_values || values`，而 merged_values 在读 values 时已被缓存，
#   只设 values 会被空缓存 {} 覆盖 —— 开关没真开上且不报错（静默失败）。
#
# ⚠ 'experiment_reporting_enabled?' 这个键名**带问号**（与其余命名不一致，疑似笔误），
#   但消费点就是这么读的，键必须照抄带 '?'，否则开了也不生效。
class EnableReportingAndVersionedAttachments < ActiveRecord::Migration[7.2]
  KEYS = %w[
    analytical_reporting_enabled
    experiment_reporting_enabled?
    versioned_attachments_enabled
  ].freeze

  def up
    settings = ApplicationSettings.first || ApplicationSettings.new
    merged = (settings.values || {}).merge(KEYS.index_with { true })
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
    if removed.empty?
      settings.destroy!
    else
      settings.save!
    end
  end
end
