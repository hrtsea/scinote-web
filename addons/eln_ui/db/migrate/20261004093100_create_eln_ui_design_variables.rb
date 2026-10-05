# frozen_string_literal: true

# ELN UI —— 实验级 DOE「设计变量」（DV）表
#
# 这张表是纯二开：SciNote 原生**完全没有** DOE / 设计变量 / 配方优化任何一块，
# 原型里那几行 DV（POE 掺量 / 滑石粉 / 相容剂 …）在真机上必须来自这里。
#
# 字段口径刻意选「结构化」而不是「一个 range 文本列」：
#   range_min / range_max / unit 三列存数值区间，categorical（如牌号）用 range 文本
#   表达取值集合，constraint 存约束说明。这样前端渲染的是**数据**而不是编出来的字符串。
#
# 空表是合法状态：实验没做 DOE 时 payload 给空数组、面板照常渲染空表（显式留白），
# 与「原型写死 3 行假变量」是两回事。
class CreateElnUiDesignVariables < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_design_variables do |t|
      t.references :experiment, null: false, foreign_key: true
      t.string :name, null: false
      # float / integer / categorical —— 与原型 expDesignVars.type 取值域一致
      t.string :var_type, null: false, default: 'float'
      t.decimal :range_min, precision: 12, scale: 4
      t.decimal :range_max, precision: 12, scale: 4
      t.string :unit
      t.string :constraint
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :eln_ui_design_variables, %i[experiment_id position]
  end
end
