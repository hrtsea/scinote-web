# frozen_string_literal: true

# 出入库流水单价快照列
#
# 与 repository_rows.unit_price 同源同语义，但落点是 ledger_records：
# 出库当时从对应 RepositoryRow.unit_price 拷贝写入。聚合项目花费时直接读快照，
# 不需要 JOIN 回 RepositoryRow 拿「当前价」——避免后续单价调整误改历史口径
# （SCN-RES-COST-3：金额冻结在流水层，不在库存层）。
#
# ⚠ additive only。
class AddUnitPriceToRepositoryLedgerRecords < ActiveRecord::Migration[7.2]
  def change
    add_column :repository_ledger_records, :unit_price, :decimal, precision: 12, scale: 4, default: 0, null: false
    # 入库记录不计入花费（SCN-RES-COST-4），但快照仍然写入，便于后续审计；
    # 不在这里加 where 过滤索引——查询路径是全量扫描 + 服务端 filter。
    add_index :repository_ledger_records, %i[created_at unit_price], name: 'idx_ledger_created_price'
  end
end
