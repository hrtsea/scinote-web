# frozen_string_literal: true

# ELN UI —— 材料类申请的【到货验收入库】写侧（ADR-0030 决定 D2/D3/D7）。
#
# 语义（请购单，不是领用单）：
#   申请时选定「进入哪个库」→ 终审通过只**解锁**验收 → 到货验收时由本服务把料**写进库存**。
#
# 做四件事，全在一个事务里（由调用方 ResourceApplicationWorkflow#apply_complete 包裹）：
#   ① 在目标库内**按名称找条目**：有则复用、无则新建（L993「到货验收**建/更新**库存」的「建」）
#   ② 把请购单价写进 `RepositoryRow.unit_price`（spec L60：物料属性，入库时由请购成本写入）
#   ③ 找/建库存单位项 `RepositoryStockUnitItem`（单位跟随申请单填写的 unit）
#   ④ 建或累加 `RepositoryStockValue`
#
# 🔴 **入库不写项目、不计花费**（SCN-RES-COST-4 / L993）：本服务**不碰** `my_module_references`，
#   也不给 Ledger 行标项目。原生 `RepositoryStockValue` 的 `after_create` / `update_data!`
#   会自动写一条 `RepositoryLedgerRecord`，其 `reference` 指向 **Repository**（不是
#   `MyModuleRepositoryRow`）—— 而花费归集只认 `reference_type = 'MyModuleRepositoryRow'`
#   （REQ-RESOURCE-COST L993），故入库行**天然**被排除。这是原生行为，不是我们刻意过滤。
#
# 🔴 出库仍然只由**任务消耗**发生（ADR-0030 D4）：本服务不做出库、不扣减。
module Scinote
  module ElnUi
    class MaterialReceiptPosting
      # 与 Workflow 的 WorkflowError 分开：这是**库存写侧**的失败，调用方需要区分
      # 「业务校验不过」与「库存结构缺失（比如目标库根本没有库存列）」。
      class PostingError < StandardError; end

      # 返回 { row:, stock_value:, row_created:, qty_before:, qty_after: }
      #
      # ⚠ `qty:` 是 ADR-0032 D5 加的**可选**覆盖：分批到货时由验货人申报「本批到货数量」，
      #   不传则沿用整单量（保持既有调用方行为不变 —— B1 历史单补录走的就是这条路）。
      #   ⚠ 它是一个**能写错数的入口**：调用方多了一条「传错数量就写错库存」的路。
      #     所以「传」与「不传」两条路径都必须有测试（见 eln_ui_receipt_verification_test.rb）。
      def self.call(application:, user:, qty: nil)
        new(application: application, user: user, qty: qty).call
      end

      def initialize(application:, user:, qty: nil)
        @app = application
        @user = user
        @qty_override = qty
      end

      def call
        item = @app.item_list.first
        raise PostingError, '申请单没有明细行，无法入库' if item.nil?

        @qty = (@qty_override.nil? ? nil : @qty_override.to_d)
        @qty = (item['qty'] || item[:qty]).to_d if @qty.nil?
        raise PostingError, '入库数量必须大于 0' unless @qty.positive?

        @name = (item['name'] || item[:name]).to_s.strip
        raise PostingError, '入库物料名称缺失' if @name.blank?

        @unit = (item['unit'] || item[:unit]).to_s.strip
        @unit_price = (item['unit_price'] || item[:unit_price]).to_d

        @repository = resolve_repository(item)
        @column = resolve_stock_column(@repository)
        @row = find_or_create_row
        write_unit_price!
        @unit_item = find_or_create_unit_item
        post_stock!

        {
          row: @row,
          stock_value: @stock_value,
          row_created: @row_created,
          qty_before: @qty_before,
          qty_after: @stock_value.amount.to_d
        }
      end

      private

      # 目标库：申请时由 create_draft 校验过「存在 + 属于当前团队」，这里再兜一次
      # （入库是不可逆的库存变动，宁可在写之前多问一句）。
      def resolve_repository(item)
        repo_id = item['repository_id'] || item[:repository_id]
        raise PostingError, '申请单未指定目标库，无法入库' if repo_id.blank?

        repo = ::Repository.find_by(id: repo_id.to_i)
        raise PostingError, '目标库不存在' if repo.nil?

        repo
      end

      # 目标库必须配有「库存」列；没有就无法承载数量——错误信息要**可行动**，
      # 否则验收人只能看到一句「入库失败」然后去问开发。
      def resolve_stock_column(repo)
        column = repo.repository_columns.find_by(data_type: 'RepositoryStockValue')
        raise PostingError, "目标库「#{repo.name}」未配置库存列，无法入库（请先在该库添加「库存」列）" if column.nil?

        column
      end

      # 按名称找/建条目。匹配口径：去空格后**不区分大小写**——「乙醇」与「乙醇 」、
      # 「PP」与「pp」都算同一条，避免每次到货都长出一条近重复条目（那是库存腐化的开始）。
      # 只看未归档的：同名的归档条目不该被复活。
      def find_or_create_row
        existing = @repository.repository_rows
                               .where(archived: false)
                               .where('LOWER(repository_rows.name) = ?', @name.downcase)
                               .first
        if existing
          @row_created = false
          return existing
        end

        @row_created = true
        @repository.repository_rows.create!(
          name: @name,
          created_by: @user,
          last_modified_by: @user
        )
      end

      # 请购成本写进物料单价（spec L60）。单价为 0 / 空时**不写**：
      # 把已有单价抹成 0 会让后续所有消耗的快照金额归零，比「不更新」糟得多。
      def write_unit_price!
        return unless @unit_price.positive?
        return unless @row.respond_to?(:unit_price)

        @row.update!(unit_price: @unit_price)
      end

      def find_or_create_unit_item
        return nil if @unit.blank?

        item = @column.repository_stock_unit_items.find_by(data: @unit)
        return item if item

        @column.repository_stock_unit_items.create!(
          data: @unit,
          created_by: @user,
          last_modified_by: @user
        )
      end

      # 建（首次）或累加（再次到货）。
      # ⚠ `RepositoryStockValue.new_with_payload` 读键的姿势**不一致**：
      #   它用 `payload[:amount]`（符号）却用 `payload['unit_item_id']`（字符串）。
      #   直接喂一个普通 Hash 会静默丢单位；用 HashWithIndifferentAccess 让两种写法都成立。
      def post_stock!
        @stock_value = @row.repository_stock_value

        if @stock_value.nil?
          @qty_before = 0.to_d
          cell = @row.repository_cells.create(repository_column: @column)
          @stock_value = ::RepositoryStockValue.new_with_payload(
            ActiveSupport::HashWithIndifferentAccess.new(amount: @qty, unit_item_id: @unit_item&.id),
            repository_cell: cell,
            created_by: @user,
            last_modified_by: @user
          )
          @stock_value.save!
        else
          @qty_before = @stock_value.amount.to_d
          # 单位没填就沿用该条目原有单位——传 nil 会把已有单位清掉（update_data! 会 find_by(id: nil)）
          @unit_item ||= @stock_value.repository_stock_unit_item
          @stock_value.update_data!(
            ActiveSupport::HashWithIndifferentAccess.new(
              amount: @qty_before + @qty,
              unit_item_id: @unit_item&.id
            ),
            @user
          )
        end
      end
    end
  end
end
