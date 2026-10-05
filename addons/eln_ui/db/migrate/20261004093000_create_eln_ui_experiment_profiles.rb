# frozen_string_literal: true

# ELN UI —— 实验二开主数据（原生**没有**承载面的那几格）
#
# 为什么必须有这张表（而不是往 experiments 加列）：
#   「实验目的 / 实验方案与方法 / 业务编号 / 项目来源 / 实验负责人」这些概念，
#   SciNote 原生**一个都没有**：
#     experiments 只有 name / description / started_at / done_at / due_date，没有结构化的
#     「目的」「方法步骤」「负责人」「来源」。
#   按项目铁律「不动原生数据库」，这里**不**给原生表加列，而是在本 addon 内建自有表，
#   以 experiment_id 关联 —— 原生 schema 一字未改，二开数据全在 eln_ui_* 里。
#
# 取不到的格一律留白（payload 层给 nil / '—'），绝不编造；
# 业务编号优先取这里的 business_code，取不到再退回原生 Experiment#code（EX + 主键）。
#
# 这张表同时还是「页面文案真值化」的落点：原型里那些写死的演示文案
# （150°C 蒸汽环境… Dow ADH-6066… 拉伸剪切强度 ≥ 8.0 MPa）在真机上必须由这里的数据顶上，
# 没有数据就留白，不能把演示文案当真值渲染。
class CreateElnUiExperimentProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_experiment_profiles do |t|
      t.references :experiment, null: false, foreign_key: true, index: { unique: true }
      # 业务编号（如 ELN-EXP-2026-001）：原生 Experiment#code 是 EX + 主键，
      # 那是**系统编码**不是业务编号，需要二开定义可读编号时落这里；nil 则回落 code。
      t.string :business_code
      # 实验目的 / 实验方案与方法：原生无承载面（description 是富文本、且不是结构化的目的）
      t.text :purpose
      t.text :method
      # 显式负责人（可选）。没有显式指派时 payload 会退回 UserAssignment → created_by 推导，
      # 推导不到才留白。这里只是「人工指定」的落点。
      t.references :owner_user, foreign_key: { to_table: :users }
      # 项目来源（原生完全没有这个字段）—— 只在二开口径下才有值。
      t.string :source
      t.timestamps
    end
  end
end
