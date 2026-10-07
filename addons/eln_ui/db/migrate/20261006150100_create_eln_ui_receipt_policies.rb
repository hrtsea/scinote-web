# frozen_string_literal: true

# 到货验收的项目级策略（eln_ui_receipt_policies · REQ-RES-RECEIPT / ADR-0032）
#
# 只存**一个**开关：`allow_self_verification`（验货人可否是申请人本人）。
#
# ⚠ 为什么不挂到 `eln_ui_project_approvers`（名单表）上、也不用「是否在 receipt 名单里」隐含：
#   「名单」回答的是**谁能验**，「本项目允不允许验自己的单」回答的是**能不能自验** ——
#   两个问题。隐含方案（把 PI 放进名单就等于允许自验）会让「名单必须有 PI 才能让他验货」
#   与「本项目不接受他验自己的单」两件事互相绑死，拆不开。
#   用户 2026-10-06 明确选了**独立开关**。
#
# 🔴 阈值**不在这里**：阻断阈值走与 `service_result_strike_limit` 同一处模块级配置
#   （`Scinote::ElnUi.receipt_pending_block_limit`）。理由是「机制只能一份」——
#   服务逾期冻结与材料未验货冻结是一对镜像，阈值若一个按项目一个全局，就是两套口径。
class CreateElnUiReceiptPolicies < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_receipt_policies do |t|
      # 每项目**至多一行**（unique index）：策略是项目级单值，不做历史版本
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.boolean  :allow_self_verification, null: false, default: false
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
