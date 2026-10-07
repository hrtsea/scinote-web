# frozen_string_literal: true

# ELN UI —— 库存删除时同步作废明细行（SCN-RES-CONSUME-1 后半句「同步失效或冲正」）
#
# ## 为什么需要
#   物料明细行在 addon 自有表 eln_ui_consume_records 里，溯源指向原生
#   RepositoryLedgerRecord。原生那侧有一条**销毁链**：
#     repository_stock_value.rb:14  has_many :repository_ledger_records, dependent: :destroy
#     repository_stock_value.rb:12  has_one :repository_cell, as: :value, dependent: :destroy
#   删库存条目 / 删 StockValue 时，Ledger 行会一起消失，但**明细行不会**——
#   它变成孤儿行，继续参与花费汇总（Σ amount），账面虚高且再也对不上账。
#
#   ⚠ 注意区分两条「冲正」路径：
#     ① 负 delta 的**新** Ledger 行（改消耗量/还回）—— 由
#        ConsumeRecord.sync_material_from_ledger! 登记成负金额明细行，自然对冲，
#        不需要本decorator；
#     ② Ledger 行**被销毁**（本文件）—— 原生没有「撤销单条流水」的入口，
#        唯一消失路径就是整条依赖链销毁。才需要主动作废明细行。
#
# ## 为什么用装饰器而不是改原生 model
#   addon 铁律：不碰 Rails 本体、不动原生表。用 prepend 挂 after_destroy 是唯一
#   不改原生文件又能接住销毁事件的方式。
#
# ## 作废而非物理删除
#   明细行是花费审计凭据，删掉就查不到「曾经花过这笔」。作废口径 =
#   amount 归零 + 名字标记，账面立刻归位，痕迹仍在。
module Scinote
  module ElnUi
    module StockValueMaterialInvalidation
      def destroy
        # ⚠ 常量在**运行期**解析（decorator 由 to_prepare load，engine model 未必已就绪）
        klass = defined?(::Scinote::ElnUi::ConsumeRecord) ? ::Scinote::ElnUi::ConsumeRecord : nil
        return super if klass.nil?

        # 必须**先取 ledger id 再 destroy**：super 之后流水行已经没了，反查不回来。
        # 用 transaction 包住：作废失败不该让「删库存」整体失败（账目问题不阻断库存操作）。
        begin
          ::Scinote::ElnUi::ConsumeRecord.transaction(requires_new: true) do
            klass.invalidate_material_rows_for_stock_value!(self)
          end
        rescue StandardError => e
          Rails.logger.warn("[eln_ui] 作废物料明细行失败 stock_value=#{id}: #{e.class} #{e.message}")
        end
        super
      end
    end
  end
end

RepositoryStockValue.prepend(Scinote::ElnUi::StockValueMaterialInvalidation)
