# frozen_string_literal: true

# eln_ui 项目列表「收藏 / 星标」—— **按用户维度**（多用户 ELN 必须 per-user，
# 不能是 projects 上的全局 boolean 列：否则 A 收藏会让 B 也看到已收藏，语义错）。
#
# ⚠ 表名显式 eln_ui_ 前缀：与 eln_ui 其它二开表（eln_ui_consume_records /
#   eln_ui_receipt_verifications / eln_ui_task_close_requests …）同源约定，
#   避免与宿主未来可能的 project_stars 撞名。
class CreateElnUiProjectStars < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_project_stars do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }
      t.references :project, null: false, foreign_key: { to_table: :projects }
      t.timestamps
    end
    add_index :eln_ui_project_stars, %i[user_id project_id],
              unique: true, name: 'uniq_eln_ui_project_stars_user_project'
  end
end
