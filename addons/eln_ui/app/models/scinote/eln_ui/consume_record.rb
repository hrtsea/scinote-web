# frozen_string_literal: true

# 消耗/执行明细行（eln_ui_consume_records · REQ-RES-CONSUME）
#
# 规格 V1.21 L105~L108 的落点：一张二开表同时收纳「已消耗的物资」与「已测试过的服务」。
# ⚠ 表结构理由见迁移文件；这里只做 ORM 形状 + 归集散装，不含审批/消耗链路逻辑
#   （物资登记在 decorator `MmrUnitPriceSnapshot`、服务登记在 seed/service 层）。
#
# ⚠ 两条硬约束（来自 spec）：
#   · L106 物资行**与 Ledger 一一对应**，不得双写失真 → 只有 decorator 能建物资行；
#     数据库侧用 (source_type, source_id) 唯一索引兜底，重复登记直接 PG::UniqueViolation。
#   · L107 服务行**不写 Ledger** → 服务行的 source_type 是 ResourceApplication（现阶段），
#     与 Ledger 行天然不重叠。
#
# ⚠ 与 eln_ui 其他 model 同源铁律：
#   · 表名显式 self.table_name（否则 Rails 推不出 eln_ui_consume_record 复数歧义）；
#   · class_name 一律带 `::`（避开宿主 Scinote::Project / Scinote::User 常量遮蔽）；
#   · 类体必须裹在 module Scinote::ElnUi 里（engine eager load 路径）。
module Scinote
  module ElnUi
    class ConsumeRecord < ActiveRecord::Base
      self.table_name = 'eln_ui_consume_records'

      # ---- 行类型（spec L105：同一张表收纳两类行）----
      KINDS = %w[material service].freeze

      # 服务行结果状态（spec L109：验收通过才计入项目花费）
      RESULT_STATUSES = %w[pending_acceptance settled].freeze

      belongs_to :project, class_name: '::Project', inverse_of: false
      belongs_to :user,    class_name: '::User',    optional: true, inverse_of: false

      # ---- 溯源 ----
      # ⚠ 必须是 **optional**：溯源是「记下来源」，不是 FK。执行单表落地前
      #   source 指向的那一侧可能根本不存在（申请单、将来的执行单），强校验会
      #   直接把登记动作打回（实测报「Source must exist」→ 服务明细一条都建不出来）。
      belongs_to :source, polymorphic: true, optional: true

      validates :kind, inclusion: { in: KINDS }
      validates :quantity, presence: true
      validates :amount, presence: true
      validates :result_status, inclusion: { in: RESULT_STATUSES }, allow_nil: true

      # ---- 金额口径 ----
      # spec L105：金额 = 数量 × 单价（快照）。单价缺失时按 0 计入（快照语义：
      # 快照机制上线前的历史行 unit_price 本就是 0，不得事后回填）。
      def amount_calculated
        (quantity.to_d * unit_price.to_d).round(2)
      end

      def material?
        kind == 'material'
      end

      def service?
        kind == 'service'
      end

      def settled?
        result_status == 'settled'
      end

      # spec L109：待验收的服务行不计花费（验收通过才转 settled 计入）
      def costable?
        material? || settled?
      end

      # ---- 幂等 upsert： Ledger 行 → 明细物资行 ----
      # spec L106「与 Ledger 行一一对应，同快照单价」。decorator 与回填脚本共用本方法：
      # 已存在则**跟随 Ledger 快照刷新**（金额以流水为准），不存在则新建。
      def self.sync_material_from_ledger!(ledger:, project_id: nil, user: nil)
        project_id ||= ledger.my_module_references&.dig('project_id')
        return nil if project_id.nil?

        row = ledger.repository_row
        occurred = ledger.created_at || Time.current

        record = find_or_initialize_by(source_type: 'RepositoryLedgerRecord', source_id: ledger.id)
        record.assign_attributes(
          kind: 'material',
          name: row&.name.to_s,
          quantity: ledger.amount.to_d.abs,
          # 单位：优先用流水行当时拷下来的快照 unit，回落到库存单位项
          unit: ledger.unit.presence ||
                (ledger.repository_stock_value&.repository_stock_unit_item&.data),
          unit_price: ledger.unit_price.to_d,
          # ⚠ amount **必须带符号**（与 Ledger 同源同公式）：原生任务行
          #   amount 正 = 消耗、负 = 还回（RepositoryStockLedgerZipExport L56）。
          #   取绝对值会把「还回冲减」变成「额外增加」——实测还回 3 件被记成
          #   +¥300 而非常见的 -¥300，花费从 ¥700 虚涨到 ¥1,300。
          amount: (ledger.amount.to_d * ledger.unit_price.to_d).round(2),
          occurred_at: occurred,
          project_id: project_id,
          user: user || ledger.user
        )
        record.save!
        record
      end
    end
  end
end
