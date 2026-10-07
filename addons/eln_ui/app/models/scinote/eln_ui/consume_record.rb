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

      belongs_to :project, class_name: '::Project', inverse_of: false
      # ⚠ 2026-10-05 试过改成 registered_by（语义上「谁登记的」比「所属用户」准），
      #   但表里那列就是 `t.references :user` → user_id，改名后 Rails 找 registered_by_id
      #   直接 MissingAttributeError，19 个用例红。要真改名得连带加一条迁移，
      #   目前不值得 —— 先留着 user，命名这笔账记在这里。
      belongs_to :user,    class_name: '::User',    optional: true, inverse_of: false

      # ---- 溯源 ----
      # ⚠ 必须是 **optional**：溯源是「记下来源」，不是 FK。执行单表落地前
      #   source 指向的那一侧可能根本不存在（申请单、将来的执行单），强校验会
      #   直接把登记动作打回（实测报「Source must exist」→ 服务明细一条都建不出来）。
      belongs_to :source, polymorphic: true, optional: true

      # ---- 行类型（spec L105：同一张表收纳两类行）----
      # 🔴 2026-10-05 试过换成 enum，**实测不能用，已回退**：宿主里 enum 作用在 string 列上
      #   会把值序列化成整数下标再 cast 成字符串（探针：kind_for_database => "0"），
      #   enum 生成的 material? / service? / settled? 因此恒 false（17 failures + 6 errors）。
      #   要用 enum 得先把这两个列改成 integer（存储语义变更），单独决策。
      KINDS = %w[material service].freeze

      # 服务行结果状态（spec L109：验收通过才计入项目花费），同上不能用 enum。
      RESULT_STATUSES = %w[pending_acceptance settled].freeze

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
      #
      # 🔴 SCN-RES-CONSUME-5（设备模板库存**不产生**明细行）：判定收口在这里，
      #   不是读侧 —— 读侧剔（res_center_payload 的 cost/consume block）只保证「不计入花费」，
      #   设备消耗行仍然躺在明细表里，spec 要求的是「**不产生**」。
      #   ⚠ 写侧 fail-closed 只在「规则不可判」（EquipmentTemplateFilter.probe 拿不到）时触发；
      #     「团队确实没配设备模板」**不**触发 —— 否则全部物资被拒、花费恒 ¥0（已修过一次的老 bug）。
      def self.sync_material_from_ledger!(ledger:, project_id: nil, user: nil)
        return nil if Scinote::ElnUi::EquipmentTemplateFilter.skip_material_row?(ledger)

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
          #   → 也正因为这里**带符号**，原生「冲正」表现为一条负 delta 的新 Ledger 行，
          #     它自然会被登记成负金额明细行，两者对冲后花费归零（SCN-RES-CONSUME-1 后半句
          #     的「冲正」路径已由本方法覆盖，无需额外分支）。
          amount: (ledger.amount.to_d * ledger.unit_price.to_d).round(2),
          occurred_at: occurred,
          project_id: project_id,
          user: user || ledger.user
        )
        record.save!
        record
      end

      # ---- SCN-RES-CONSUME-1 后半句：Ledger 行被冲正/撤销 → 明细行同步失效 ----
      #
      # ⚠ 上面的「冲正」路径（负 delta 新行）已自然对冲；这里收的是**另一条**消失路径：
      #   `RepositoryStockValue has_many :repository_ledger_records, dependent: :destroy`
      #   （repository_stock_value.rb:14）—— 删库存条目 / 删 stock value 时，Ledger 行
      #   整体消失，而明细行是 addon 自己的表、**不会**跟着删 → 变成继续计花费的孤儿行。
      #   本方法由 StockValue 销毁链路调用，把该库存下所有物料明细行一并作废。
      #
      #   为什么是「作废」而不是物理删除：明细行是花费审计凭据，删了就查不到「曾经花过」。
      #   作废口径 = amount 归零 + 名字打上作废标记，与「取绝对值/算错」区分得开。
      def self.invalidate_material_rows_for_stock_value!(stock_value)
        return 0 if stock_value.nil?

        # 🔴 走**外键列** repository_stock_value_id，不绕 repository_cell 反查：
        #   repository_stock_values 根本没有 repository_cell_id 列（cell 侧是
        #   value_type/value_id 多态指回来），按 cell 查会直接 PG::UndefinedColumn。
        #   ⚠ reference_type 判据**不够**：入库行的 reference 指向 repository，
        #   任务消耗行指向 MyModuleRepositoryRow —— 两类都不带 reference_type='RepositoryStockValue'，
        #   只有外键列能一把捞全（否则删一个库存会漏掉它名下所有流水行）。
        ledger_ids = ::RepositoryLedgerRecord
                     .where(repository_stock_value_id: stock_value.id)
                     .pluck(:id)
        return 0 if ledger_ids.empty?

        rows = where(source_type: 'RepositoryLedgerRecord', source_id: ledger_ids)
                .where.not(amount: 0)
        count = rows.count
        rows.update_all(
          amount: 0,
          name: '（已作废：来源库存已删除）',
          updated_at: Time.current
        )
        count
      end

      # ---- 幂等 upsert： 服务申请单 → 明细服务行 ----
      # spec L107「服务不写 Ledger（无库存可扣），执行完成直接登记一行」。
      # 与物资行对称：已存在则跟随档案快照刷新（金额以档案为准），不存在则新建。
      #
      # ⚠ 登记数量 = **申请单上最终审批通过时提交的服务次数**（SCN-RES-TEST-1），
      #   不是此刻的 qty、也不由系统臆造默认值。
      # ⚠ 单价一律取**服务档案快照**（spec L986：档案是服务目录的唯一载体、
      #   单价来源），不接受调用方传价 —— 传价就等于给花费行留了个说不清来历的口子。
      #
      # 除了这里是本 addon 唯一的服务行写入方之外，材质行仍只由
      # sync_material_from_ledger! 建；两条路径分开写是为了不让「Ledger 一一对应」
      # 这条硬约束被服务行搅浑。
      def self.sync_service_from_application!(app:, occurred_at: nil)
        item = app.item_list.first
        return nil if item.blank?
        return nil if item['kind'].to_s != 'service'

        # ⚠ 兜底一律 fail-closed：服务行没绑到档案条目 = 单价没有来源，
        #   宁可登记不下去（抛错给 controller → 422），也不静默按 ¥0 落一行——
        #   那会在花费页签上留一条「¥0 测试服务」，账面看着平，实际口径是坏的。
        catalog = ::Scinote::ElnUi::ServiceCatalog.find_by(id: item[:serviceCatalogId])
        if catalog.nil?
          raise ::Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError,
                '该服务申请未绑定测试表征服务档案条目，登记服务行需要档案提供单价与验收配置'
        end

        quantity = item[:qty].to_d
        unit_price = catalog.snapshot_price

        record = find_or_initialize_by(source_type: SERVICE_SOURCE_TYPE, source_id: app.id)
        record.assign_attributes(
          kind: 'service',
          name: item['name'].presence || catalog.name,
          quantity: quantity,
          # spec SCN-RES-TEST-1：服务行的单位固定「次」
          unit: '次',
          unit_price: unit_price,
          amount: (quantity * unit_price).round(2),
          occurred_at: occurred_at || Time.current,
          project_id: app.project_id,
          # 操作人取**申请人**（谁执行/消费这笔服务），不是「点完成的那个复核人」——
          # 与物资行口径一致（Ledger.user = 出库人），花费按人归集才不会记错。
          user: app.requestor,
          # spec L1010：需验收 → 登记即「待验收」不计花费；不需验收 → 登记即计入。
          result_status: catalog.acceptance_required? ? 'pending_acceptance' : 'settled'
        )
        record.save!
        record
      end

      # 服务行的溯源 source_type（与物资行的 'RepositoryLedgerRecord' 并列）。
      # ⚠ 这个值必须等于 ResourceApplication 的 base_class 名，否则通过
      #   `belongs_to :source` 关联读回来时 constantize 不到同一个类。
      SERVICE_SOURCE_TYPE = 'Scinote::ElnUi::ResourceApplication'
    end
  end
end
