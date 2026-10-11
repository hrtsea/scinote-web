# frozen_string_literal: true

# 立项时间（＝项目**批准**日期）的承载列。
#
# ⚠ 为什么列名是 approved_on 而不是 founded_on：
#   用户 2026-10-11 澄清「立项时间不是创建时间，是项目批准时间」。列名用 approved，
#   是为了让「这是批准日期、不是 created_at」在代码里自解释 —— 否则后来者极可能
#   顺手用 projects.created_at 回填，把两个完全不同的语义塞进同一格。
#
# ⚠ 为什么不是给 projects 加列：铁律「原生表一字不动」，且 created_at 是系统时间戳
#   （审计 / 排序 / 迁移对账都依赖），业务字段不借住系统列。
# ⚠ 未登记（NULL）时页面**留白（—）**，不回落 created_at —— 拿创建时间冒充批准日期是编造值。
class AddApprovedOnToElnUiProjectProfiles < ActiveRecord::Migration[7.2]
  def change
    add_column :eln_ui_project_profiles, :approved_on, :date
  end
end
