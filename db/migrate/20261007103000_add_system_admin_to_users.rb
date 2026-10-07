# frozen_string_literal: true

# 实例级系统管理员标志位
#
# 用于限制 workspace（Team）的创建权限：只有被标记为 system_admin 的用户
# 才能在「设置 → Workspaces」界面新建 workspace
# （见 app/permissions/organization.rb 的 create_teams 权限）。
#
# 与 per-team 的 Owner（team_manage）解耦：系统管理员是跨 team 的实例级概念，
# 普通用户在某个 team 内的 Owner 能力完全不受影响。
#
# ⚠ additive only。
class AddSystemAdminToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :system_admin, :boolean, default: false, null: false
  end
end
