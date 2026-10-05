# frozen_string_literal: true

# 库存条目单价快照列
#
# 存在理由：项目花费（SCN-RES-COST-1）口径 = Σ(amount × unit_price)，
# 而 RepositoryRow 本身没有单价列（单价在 repository_stock_value 里是 amount，
# 不是 price）。在 LedgerRecord 上落地快照，保证出库当时的价格被记录，
# 后续 RepositoryRow 单价变化不影响历史花费（memory §2 已锁定）。
#
# ⚠ additive only：不改既有列、不删约束、可逆。
class AddUnitPriceToRepositoryRows < ActiveRecord::Migration[7.2]
  def change
    add_column :repository_rows, :unit_price, :decimal, precision: 12, scale: 4, default: 0, null: false
    # 走「按项目查行级单价」的查询路径会扫这个索引；
    # 库存模板自身的「按行查单价」属 O(1) 主键，不需要索引。
    add_index  :repository_rows, :unit_price, where: 'unit_price > 0', name: 'idx_rows_unit_price_nonzero'
  end
end
