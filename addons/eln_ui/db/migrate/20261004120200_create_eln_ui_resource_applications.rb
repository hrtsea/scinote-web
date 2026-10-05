# frozen_string_literal: true

# 资源申请单（资源中心 · 资源申请 tab + 申请详情页的数据源）
#
# 存在理由：SciNote 原生「Protocol 协议」流程是 MyModule 内部的 SOP 描述，
# 跟「我要领用 20 kg PP 基料 / 申请 2 次 DSC 测试」这种**外部资源申请**是两回事，
# 原生没对应模型（memory §2 已锁定）。故在 eln_ui addon 自有表挂项目级资源申请单。
#
# 工作流（二段式审批，SCN-RES-APPROVE-1~5）：
#   draft            → 草稿（仅申请人可见可改）
#   submitted        → 已提交（小组组长待审）
#   group_approved   → 小组组长通过（项目负责人待审）
#   project_approved → 项目负责人通过（可执行 = Ledger 写流水）
#   rejected         → 任一环节驳回
#   completed        → 已出库 / 服务已执行（终态）
#
# items 用 jsonb 存：[{kind:'material'|'service', name, qty, unit_price, repository_row_id?}]
# —— 不拆 lines 表：申请单的「行项目」是拟定的、不进入库存账本，
#   最终执行走原生 RepositoryLedgerRecord（已有 polymorphic reference + 快照列）。
class CreateElnUiResourceApplications < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_resource_applications do |t|
      t.references :project, null: false, foreign_key: true
      t.string  :no, null: false                          # 业务编号 SQ-YYYY-NNNN
      t.string  :status, null: false, default: 'draft'
      t.references :requestor,        null: false, foreign_key: { to_table: :users }
      t.references :group_reviewer,                    foreign_key: { to_table: :users }
      t.references :project_reviewer,                  foreign_key: { to_table: :users }
      t.jsonb   :items, null: false, default: []
      t.text    :note                                   # 申请备注 / 驳回理由
      t.datetime :submitted_at
      t.datetime :group_approved_at
      t.datetime :project_approved_at
      t.datetime :completed_at
      t.timestamps
    end

    # 业务编号全局唯一（同一团队内手编）
    add_index :eln_ui_resource_applications, :no, unique: true
    # 列表查询路径：按项目 + 状态 + 提交时间
    add_index :eln_ui_resource_applications, %i[project_id status submitted_at]
    # 「我提交的」快捷筛选
    add_index :eln_ui_resource_applications, %i[requestor_id status]
  end
end
