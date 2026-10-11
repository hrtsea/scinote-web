# frozen_string_literal: true

# ELN UI —— 项目二开主数据（原生没有承载面的那三格）
#
# 为什么必须有这张表：项目详情页「项目基础信息」9 字段里，「项目编号 / 项目来源 /
# 项目状态（五态）」三格在原生 projects 表里一列都没有。
#
# 迁移考古结论（2026-10-11）：主 app 32 个 projects 相关迁移 + 4 个 addon 全量迁移中
# 从未出现过 code / source / status 这三个概念；项目的「负责人 / 起止 / 描述」是
# 20250410093420_add_management_columns_to_project_and_experiment 那批加的，与本表无关。
# 按铁律「原生表结构一字不动」，这里在 addon 内建自有表，以 project_id 关联。
#
# 为什么必须与两层 *_profiles 同构：
#   eln_ui_experiment_profiles（business_code / source / purpose / method / owner_user）
#   eln_ui_task_profiles       （business_code / source / purpose / plan / owner_user）
# 实验层与任务层早已用这套范式补原生缺字段，独缺项目层这一张 —— 本迁移补齐三层同构。
#
# ⚠ status 不用 enum：宿主 string 列上用 enum 会把值序列化成整数下标再 cast 回字符串
#   （ReceiptVerification / ConsumeRecord#kind 实测踩过：谓词恒 false）。
# ⚠ 本表不做第二套归档状态机：「已结题」必须同时落到原生 projects.archived，
#   由归档语义联动 SCN-PM-ARCH-2（禁建任务）。
class CreateElnUiProjectProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_project_profiles do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      # 业务编号（如 ELN-PROJ-2026-018）。没有二开编号时 payload 回落 #{project.id}
      # —— 那是系统主键不是业务编号，取不到就别装作有。
      t.string :business_code
      # 项目来源（原生完全没有这个字段）—— 只在二开口径下才有值
      t.string :source
      # 项目状态（二开五态口径）。本轮只接真实存在的一档：closed 对 原生 archived；
      # 其余四态预留（UI 显式留白，不得让用户选了之后无处可存）。
      t.string :status
      t.timestamps
    end
  end
end
