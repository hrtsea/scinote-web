# frozen_string_literal: true

# OPEN-11 —— 把「项目的新建实验默认可见性」从**原生 projects 表的一根列**
# 搬到 addon 自有表。
#
# 为什么搬（这是本项目铁律的硬要求）：
#   `projects.experiment_visibility_strategy` 是 addon 引入的概念，宿主原版没有 ——
#   但它落在**原生表**上。虽然是纯加法（default 0 = 原生行为，不改变任何既有语义），
#   代价仍然是：卸载 addon 会留一根孤儿列，宿主 schema 不再是原版。
#   项目铁律是「不碰 Rails 本体/原生表；原生无承载面概念用 addon 自有表」，
#   所以这个事实该住在自己的表里（同 manual_grants / eln_ui_* 的做法）。
#
# 表语义：**只记录「偏离原生默认」的项目**。
#   没有行 = inherit（原生行为，不需要记录）。只有被 PI 显式设成 isolated 的项目有行；
#   PI 把它改回 inherit 时行被删除 —— 于是「表里有几行 = 有几个项目偏离默认」，
#   一眼能数（生产库 294 个项目里只有 47 个）。
#
# ⚠ 不加外键：宿主 projects 表不在本 addon 手里，加 FK 会让「删项目/归档项目」
#   这类原生操作在本表上撞约束（同 eln_ui_project_approvers 的处置）。
#
# ⚠ 原生列**保留不删**（不 drop 原生结构，这是铁律的另一半）：
#   它从此不再被读写，成为一根无害的孤儿列。真要清理也是宿主的事，不是 addon 能做的。
class CreateAccessControlProjectStrategies < ActiveRecord::Migration[7.0]
  def change
    create_table :access_control_project_strategies do |t|
      t.bigint  :project_id, null: false
      t.integer :strategy,   null: false, default: 0
      t.timestamps
    end

    # 一个项目最多一行
    add_index :access_control_project_strategies, :project_id,
              unique: true, name: 'idx_ac_project_strategies_on_project'
  end
end
