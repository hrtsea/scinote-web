# frozen_string_literal: true

# 项目花费登记行（挂在 Project 上）。存在理由：REQ-RES-COST 的全自动口径
# （RepositoryRow.unit_price 快照 × Ledger 消耗 + REQ-RES-CONSUME 明细）尚未落地，
# 先给「按类别登记的花费行」一张自有表 —— 页签有真数据可读，且将来全自动口径
# 上线后这里可以整体退役或降级为「人工调整行」。
#
# ⚠ 行语义与原型 mock.projectCost.rows 一致：**一行 = 一个类别的汇总行**
#   （category / source 数据来源说明 / basis 金额算法 / amount 金额），
#   总额与占比由 payload 服务端现算，不在表里存汇总。
class CreateElnUiProjectCostItems < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_project_cost_items do |t|
      t.references :project, null: false, foreign_key: true
      t.string :category, null: false                 # 材料 / 测试表征 / …
      t.text :source                                  # 数据来源说明
      t.string :basis                                 # 金额算法
      t.decimal :amount, precision: 12, scale: 4, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :eln_ui_project_cost_items, %i[project_id position]
  end
end
