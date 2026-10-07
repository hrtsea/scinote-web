# frozen_string_literal: true

module Scinote
  module ElnUi
    # 项目花费归集 —— **单一真源**（spec V1.25 · SCN-DASH-9 对账不变式）
    #
    # 为什么必须有它：
    #   工作台「项目总花费」卡要下钻到资源中心「花费」页签（本轮 Q4-A / Q5-A）。
    #   两侧若各写一份 sum，任一侧改剔除规则，用户就会在同一条链路上看见两个数字。
    #   **不变式：卡片上显示的金额 ≡ 点进去那个页面显示的金额**（金额格式化也统一，
    #   见 Scinote::ElnUi::MoneyFormat）。
    #
    # 口径（spec L105~L109，同 REQ-RESOURCE-COST / REQ-RES-CONSUME）：
    #   1. 唯一对外数据源 = 消耗/执行明细表 eln_ui_consume_records；
    #   2. 物资行：剔掉**设备模板库存**产生的消耗行（SCN-RES-COST-6）；
    #      服务行：只计已结算（settled —— spec L109「验收通过才计入项目花费」）；
    #   3. 金额**带符号**（正=消耗、负=还回），直接相加即为净额 —— 取绝对值会把
    #      「还回冲减」算成「额外增加」。
    #
    # ⚠ **不许类级 memo**（`def self.x; @x ||= …`）——跨团队/跨用例永不失效，
    #   这是本仓库踩过两次的假绿源头。复用走**实例**（一次调用一个实例）。
    #
    # ⚠ 性能取舍：行级剔除（设备模板）必须反查 Ledger → 库存行 → Repository，
    #   没法靠一句 SQL 收完；所以这里接的是**行**（ Array / relation 都行），
    #   资源中心那种「本来就要全量明细做展示」的场景不会白查第二遍。
    #   行数上限是**团队级**（不是全库），当前数据量级可接受；真撑不住就给
    #   ConsumeRecord 落一个 `chargeable` 缓存列（写侧判定，读侧不猜）。
    class ProjectCosts
      Result = Struct.new(:material, :service, :total, keyword_init: true)

      # ① 按项目范围起算（工作台：只要一个数）
      def self.call(project_ids)
        new(project_ids: project_ids).call
      end

      def self.total(project_ids)
        call(project_ids).total
      end

      # ② 按已有明细行起算（资源中心：本来就要全量明细做展示，别再查一遍）
      def self.for_rows(rows)
        new(rows: rows)
      end

      def initialize(project_ids: nil, rows: nil)
        @project_ids = project_ids
        @rows = rows
      end

      # `#call` 与 `#chargeable_rows` 共用同一份过滤结果 —— 同一调用内只过一遍。
      def call
        @call ||= begin
          material = sum(chargeable_rows.select(&:material?))
          service = sum(chargeable_rows.select(&:service?))
          Result.new(material: material, service: service, total: (material + service).round(2))
        end
      end

      # 计入花费的明细行（按 #chargeable? 过滤后的 Array）
      def chargeable_rows
        @chargeable_rows ||= rows.select { |cr| chargeable?(cr) }
      end

      def rows
        @rows ||= ::Scinote::ElnUi::ConsumeRecord.where(project_id: @project_ids)
      end

      # 单行是否计费：物资 + 非设备模板库存；服务 + 已结算
      #
      # ⚠ `ConsumeRecord#costable?` = `material? || settled?`，正好就是
      #   spec L109 的服务侧口径，这里**不重复写一遍 result_status == 'settled'**。
      def chargeable?(cr)
        return false if cr.material? && equipment_row?(cr)

        cr.costable?
      end

      # SCN-RES-COST-6 在**明细表侧**的剔除：设备模板库存的消耗不产生花费。
      #
      # 🔴 三个「return false」语义各不相同，别合并：
      #   · 不是 Ledger 来源（服务行/手动登记）→ 不适用本规则，正常计；
      #   · 查不到设备模板（规则不可判）→ **fail-open** 照计（与 Ledger 侧
      #     `cost_eligible?` 的 fail-closed 不同 —— 这是历史既成事实，本轮只做
      #     位置搬迁、**不改口径**；差异由 res_center 的对账块
      #     `reconciliation.equipmentRuleActive` 显式报出来）；
      #   · 找到行但不在设备仓库 → 正常计。
      def equipment_row?(cr)
        return false unless cr.source_type == 'RepositoryLedgerRecord'
        return false unless equipment_rule_active?

        ledger = ::RepositoryLedgerRecord.find_by(id: cr.source_id)
        return false if ledger.nil?

        row = ledger.repository_stock_value&.repository_cell&.repository_row
        row.present? && equipment_repo_ids.include?(row.repository_id)
      end

      # 规则**能不能判**（≠「团队有没有设备模板」，两种「空」的区别见 EquipmentTemplateFilter 头注释）。
      #   ⚠ 复用它自己的 `rule_active?`，不要在这里重写 `!probe.nil?` —— 那是同一件事的
      #   第二份定义，改一处漏一处正是本项目反复踩的坑。
      def equipment_rule_active?
        ::Scinote::ElnUi::EquipmentTemplateFilter.rule_active?
      end

      def equipment_repo_ids
        @equipment_repo_ids ||= ::Scinote::ElnUi::EquipmentTemplateFilter.equipment_repository_ids
      end

      private

      def sum(list)
        list.sum { |cr| cr.amount.to_d }.round(2)
      end
    end
  end
end
