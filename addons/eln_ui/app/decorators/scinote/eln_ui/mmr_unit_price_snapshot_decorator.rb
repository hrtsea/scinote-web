# frozen_string_literal: true

# ELN UI —— 任务消耗快照单价（SCN-RES-COST-2 · 「花费↔消耗明细对应上」的前置件）
#
# 为什么存在：原生 MyModuleRepositoryRow#deduct_stock_balance 建 Ledger 消耗行时
# **不写 unit_price** —— 流水行没有单价，花费核算 Σ(amount × unit_price) 就没有
# 真源，花费页签与消耗/执行明细永远「对不上」。本 decorator 在原生消耗链路
# 完成后，把 RepositoryRow.unit_price（出库瞬间的物料单价）补写进刚建好的
# 流水行；之后物料改价不影响已发生花费（快照语义，规格 V1.21 L852）。
#
# 边界：
#   · 入库行不在此链路（SCN-RES-COST-4：入库不计花费），单价留空不受影响；
#   · ⚠ unit_price 列默认 **0 不是 NULL**（生产实查 id 8/9 实锤），所以判空要用
#     「to_d.zero?」，用 present? 会把 0 当已填值跳过写入（快照永远落不下去）；
#   · 已有非 0 快照不覆盖（防误清别的写入方）；
#   · 同一 MMR 多次 consume_stock 会产生多条流水行，取 id 最大（本次刚建那条）；
#   · 原生 deduct 只写 Ledger 不写明细，故**登记明细行的动作在本 decorator 末尾补**（下面第 2 段）。
#
# 第 2 段：spec L106「明细表同步登记一行、与 Ledger 行一一对应（同快照单价），
# 不得单独录入造成双写失真」——登记与单价写在同一个方法里，保证二者同源同批：
#   流水行（RepositoryLedgerRecord） ←→ 明细行（Scinote::ElnUi::ConsumeRecord）
# 幂等由明细表 (source_type, source_id) 唯一索引 + find_or_initialize_by 双保险。
module Scinote
  module ElnUi
    module MmrUnitPriceSnapshot
      def deduct_stock_balance
        super
        rec = RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow',
                                           reference_id: id).order(id: :desc).take
        return if rec.nil?

        snapshot = repository_row.unit_price.to_d
        rec.update_column(:unit_price, snapshot) if rec.unit_price.to_d.zero? && snapshot.positive?

        # ⚠ 常量在**运行期**解析（decorator 在 to_prepare 时 load，engine model 未必已就绪）
        ::Scinote::ElnUi::ConsumeRecord.sync_material_from_ledger!(ledger: rec)
      end
    end
  end
end

MyModuleRepositoryRow.prepend(Scinote::ElnUi::MmrUnitPriceSnapshot)
