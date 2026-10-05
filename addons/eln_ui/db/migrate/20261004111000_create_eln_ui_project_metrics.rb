# frozen_string_literal: true

# 项目指标（与 20261004093000_create_eln_ui_experiment_profiles 同构、挂在 Project 上）。
# 存在理由：原生 projects 表**没有任何指标列**，而原型项目详情页「项目指标」页签
# 要展示「指标名 / 目标值 / 当前值 / 是否达标」（mock.js projectMetrics 同形状）。
#
# 按铁律：**原生表结构一字不动**，二开内容一律进 eln_ui_* 自有表，以 project_id 关联。
class CreateElnUiProjectMetrics < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_project_metrics do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :target
      t.string :current
      t.boolean :ok, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :eln_ui_project_metrics, %i[project_id position]
  end
end
