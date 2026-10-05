# frozen_string_literal: true

# 消耗/执行明细表（eln_ui_consume_records · REQ-RES-CONSUME，规格 V1.21 L105）
#
# 存在理由：V1.21 推翻 V1.18~V1.20 的「服务＝独立 Inventory + Stock 额度」建模，
# 改为「服务不建库存、不留额度，批准即测试，测试完成直接落台账」。于是物资与服务
# 两条路径需要一张**共同的对外数据源**：
#
#   - 物资行：库存物资走原生任务消耗（扣 Stock + 写 RepositoryLedgerRecord），
#     本表**同步登记一行**并与 Ledger 行**一一对应（同快照单价）**——
#     spec L106 明令「不得单独录入造成双写失真」，故登记动作由 decorator 在消耗
#     链路内完成，本表不提供人工录入入口；
#   - 服务行：spec L107「不写 Ledger（无库存可扣），执行完成直接登记一行」，
#     source_type 指向执行来源（现阶段 = 申请单 ResourceApplication；
#     执行单表落地后改为对应执行单模型）。
#
# spec L108：花费归集（按 project_id / 按 user_id 两种口径）**唯一对外数据源 = 本表**，
# 物资部分金额与 Ledger 同源同值（构造性保证：同一 decorator 同一批写入）。
#
# ⚠ 与 RepositoryLedgerRecord 的分工：
#   · Ledger = **原生库存流水**（物资产侧，符号语义见 RepositoryStockLedgerZipExport L56）；
#   · 本表    = **二开消费台账**（花费/明细页签对外读的一侧），
#     字段按 spec L105 齐：类型、名称、数量、单位、单价(快照)、金额、项目、操作人、发生时间，
#     服务行另含结果状态与结果文件引用。
class CreateElnUiConsumeRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_consume_records do |t|
      t.string  :kind, null: false, default: 'material'   # material = 物资消耗 / service = 服务执行
      t.string  :name, null: false                        # 物资名（冗余快照，不 join 行）／服务名
      t.decimal :quantity, null: false, precision: 15, scale: 4, default: 0
      t.string  :unit                                     # kg / 次（冗余快照）
      t.decimal :unit_price, null: false, precision: 15, scale: 4, default: 0  # 单价快照
      t.decimal :amount,     null: false, precision: 15, scale: 4, default: 0  # quantity × unit_price
      t.datetime :occurred_at, null: false                # 发生时间（默认取 Ledger/执行时间）

      t.references :project, null: false, foreign_key: { to_table: :projects }
      t.references :user,               foreign_key: { to_table: :users }      # 操作人

      # ---- 溯源（一一对应 + 幂等防重）----
      t.string  :source_type, null: false                 # RepositoryLedgerRecord / ResourceApplication
      t.integer :source_id,   null: false
      # ---- 服务行结果绑定（spec L105「服务行另含结果状态与结果文件引用」）----
      t.string  :result_status                            # pending_acceptance（待验收）/ settled（已结算）
      t.string  :result_file

      t.timestamps
    end

    # ⚠ 唯一索引 = 双写防护的硬闸门：Ledger 行只能登记一次明细，重跑 decorator/回填不产生重复行
    add_index :eln_ui_consume_records, %i[source_type source_id], unique: true,
              name: 'idx_eln_ui_consumerec_on_source'
    # 花费归集主查询路径：按项目 + 时间（spec L108 按 project_id / user_id 两口径）
    add_index :eln_ui_consume_records, %i[project_id occurred_at]
    add_index :eln_ui_consume_records, %i[user_id occurred_at]
    add_index :eln_ui_consume_records, %i[kind occurred_at]
  end
end
