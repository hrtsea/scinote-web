# frozen_string_literal: true

# ELN UI —— 项目级审批人配置表（eln_ui_project_approvers · REQ-RES-APPROVER）
#
# 为什么要有这张表（ADR-0029 / grilling Q1~Q7 裁决）：
#   二段式审批（初审 → 终审）此前用「同团队 + 非本人」宽口径当闸门 —— 那是
#   **推不出来的东西**：单据上没有任何一列写着「谁有资格批这一阶段」，
#   只能靠 Department 成员身份反推。后果是：
#     · 项目负责人无法管理审批资格（组员之间互相就能批）；
#     · 排查「为什么这个人能批」要穿过角色推断链（OPEN-1 双轨还没收敛）；
#     · 换人走流程要改 ruby 代码，不是改配置。
#   本表把审批资格变成**显式的、逐项目的、分阶段的**名单。
#
# ⚠ fail-closed：名单为空 = 该阶段无人可批，申请在该阶段原地等待。
#   不为「万一没配」兜底开仁慈 fallback —— 兜底会把新引入的显式口径
#   又变回隐式推断。冷启动出口是「一键初始化」按钮（见 ProjectApproversController#init），
#   不是自动放行。
#
# ⚠ 表结构只用原生外键列（project_id / user_id / created_by_id），
#   不加 FK 约束 —— 宿主 projects/users 表不在本 addon 手里，加 FK 会让
#   删用户/归档项目的原生操作在本表上撞约束。
class CreateElnUiProjectApprovers < ActiveRecord::Migration[7.0]
  def change
    create_table :eln_ui_project_approvers do |t|
      t.bigint :project_id, null: false
      t.string :stage, null: false
      t.bigint :user_id, null: false
      t.bigint :created_by_id, null: true
      t.timestamps
    end

    add_index :eln_ui_project_approvers, :project_id
    add_index :eln_ui_project_approvers, %i[project_id stage],
              name: 'idx_eln_ui_approvers_on_project_stage'
    # 同一项目的同一阶段，同一个人只能配一次（重复配是 UI 抖动，不是配置意图）
    add_index :eln_ui_project_approvers, %i[project_id stage user_id],
              unique: true, name: 'idx_eln_ui_approvers_uniq'
    # 反查「我有哪些项目要我审批」—— 可见范围顺着这条索引走，不用全表扫
    add_index :eln_ui_project_approvers, %i[user_id stage],
              name: 'idx_eln_ui_approvers_on_user_stage'
  end
end
