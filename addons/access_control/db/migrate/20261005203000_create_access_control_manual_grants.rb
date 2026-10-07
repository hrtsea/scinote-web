# frozen_string_literal: true

# 「PI 在这一格上显式放行过」的唯一落点（access_control_manual_grants）
#
# 为什么必须有这张表：
#   这个事实原来**没有自己的家**，只能从 UA 行上反推 ——
#     assigned == :manually  +  角色名不在 [experiment_owner, project_head]  +  角色含 experiment_read
#   反推有两个致命问题：
#     1. `assigned` 是**原生字段**。宿主后台的手工指派、别的 addon 都会写它，
#        于是「谁写的这一行」不可知；
#     2. revoke 只能按「排除两个角色名」去扫 UA 行，剩下的手动行一律打回 automatically
#        —— 也就是把**别的来源**留下的人工授权顺手撤了。
#   这不是精度问题，是语义问题：PI 是不是勾过这一格，是 addon 自己的事实，
#   按项目铁律就该落在 addon 自有表上（同 eln_ui_* 的做法），不借原生字段反推。
#
# 有了它之后：
#   grant  → 写 UA 行（可见性真正生效的地方）+ 记一行 grant
#   revoke → 查 grant 行；没有就 :noop（绝不碰任何别的来源写的 UA 行）
#   读数   → 查 grant 行；三段推断全部删掉
#
# ⚠ 不建外键：本表不引用原生表，卸载 addon 时 drop 掉即可，不给 experiments / users
#   留下任何约束依赖（同项目 eln_ui_* 表的做法）。
class CreateAccessControlManualGrants < ActiveRecord::Migration[7.2]
  def up
    create_table :access_control_manual_grants do |t|
      t.bigint :experiment_id, null: false
      t.bigint :user_id,       null: false
      # 0 = experiment（只开实验壳）｜ 1 = task（实验 + 其下任务）
      t.integer :scope,        null: false, default: 0
      t.bigint :granted_by_id
      # 放行那一刻，实验上那行 UA **本来就已经是 manually** 吗？
      # 是 → 说明那行是宿主后台手工指派给的，本 addon 没改过它，revoke 时必须原样留着；
      # 否 → revoke 把它打回 automatically 就对了（翻之前它就是这个值）。
      # 没有这一列，revoke 只能一律打回，等于替宿主撤销人工授权。
      t.boolean :was_manual,   null: false, default: false
      t.timestamps
    end

    # 唯一查询路径是「这一格有没有被放行」→ (experiment, user, scope) 唯一
    add_index :access_control_manual_grants, %i[experiment_id user_id scope],
              unique: true, name: 'idx_ac_manual_grants_on_exp_user_scope'
    add_index :access_control_manual_grants, :user_id,
              name: 'idx_ac_manual_grants_on_user'
  end

  def down
    drop_table :access_control_manual_grants
  end
end
