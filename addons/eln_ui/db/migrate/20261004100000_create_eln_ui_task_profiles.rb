# frozen_string_literal: true

# 任务级业务档案（与 20261004093000_create_eln_ui_experiment_profiles 同构、但挂在
# MyModule 上）。存在理由：原生 my_modules 32 列里**没有任何一列**能承载
# 「任务目的 / 执行计划 / 显式负责人 / 业务编号」，而 PRD §7.8.2 的「任务信息」
# 卡要展示这四样（REQ-TASK-DETAIL SCN-TASK-DETAIL-2/3）。
#
# 按铁律：**原生表结构一字不动**，二开内容一律进 eln_ui_* 自有表，以 my_module_id 关联。
class CreateElnUiTaskProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_task_profiles do |t|
      t.references :my_module, null: false, foreign_key: true, index: { unique: true }
      t.string :business_code
      t.text :purpose
      t.text :plan
      t.references :owner_user, foreign_key: { to_table: :users }
      t.string :source
      t.timestamps
    end
  end
end
