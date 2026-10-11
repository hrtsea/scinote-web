# frozen_string_literal: true

# ELN UI —— 服务端网格原语（宿主 shared/datatable/table.vue 的排序 / 切片 / 契约）
#
# 为什么抽成共用模块（2026-10-11）：
#   资源中心 5 张表（ResCenterPayload#grid_rows）与项目详情页 7 张表
#   （ProjectDetailPayload#grid_rows）需要**同一套**「服务端排序 + 切片 + JSON:API 契约」。
#   两份实现就是两份口径，迟早漂 —— 该仓铁律「同一事实只许一个真源」。
#
# 🔴 本模块的行为**逐字**搬自 ResCenterPayload 原实现（sort_rows / row_value /
#   blank_cell? / money_to_d / paginate），未做任何语义改动；迁移由
#   eln_ui_res_center_test 的既有排序/分页断言回归守着。
#
# 契约（与宿主 shared/datatable/table.vue#formatData 对齐）：
#   { data: [{ id:, type:, attributes: {…} }], meta: { total_pages:, total_count:, filtered_count: } }
#   ⚠ attributes 会被 formatData 摊平成行对象 ⇒ columnDefs.field 必须 == attributes 的键。
module Scinote
  module ElnUi
    module GridSupport
      private

      # 分页参数收口：page ≥ 1 且 ≤ 1000；per_page ∈ [1, 100]。
      # 越界值来自 URL/前端，夹住而不是抛错 —— 与 ResCenterPayload 原实现一致。
      def clamp_paging(page, per_page)
        [ [[page.to_i, 1].max, 1000].min, [[per_page.to_i, 1].max, 100].min ]
      end

      def empty_grid
        { data: [], meta: { total_pages: 1, total_count: 0, filtered_count: 0 } }
      end

      # 数值感知排序：某列「非空值全部可解析为数字」时按数字排（金额/数量/时间），否则整列按字典序。
      # 时间列是 'YYYY-MM-DD HH:MM'（零填充）⇒ 数字化后序 == 时间序，走数字分支即可。
      # 关掉客户端排序（宿主组件 comparator:()=>null），排序全部由这里收口。
      def sort_rows(rows, order)
        return rows if order.blank?

        o = order.is_a?(Array) ? order.first : order
        return rows if o.blank?

        col = (o.respond_to?(:dig) ? (o.dig(:column) || o.dig('column')) : nil).to_s
        return rows if col.blank?

        dir = (o.respond_to?(:dig) ? (o.dig(:dir) || o.dig('dir')) : nil).to_s == 'desc' ? :desc : :asc
        sym = col.to_sym

        # 整列判定（忽略空单元格，如入库行的「—」）：全可数字化 ⇒ 数字序，否则整列字典序。
        # ⚠ 必须整列判定，不能逐值判定 —— 否则「名称」这类列里带数字的行会被拆进数字桶，
        #   与其余行互相穿插，看起来像乱序。
        filled = rows.map { |r| row_value(r, sym, col) }.reject { |v| blank_cell?(v) }
        numeric = filled.any? && filled.all? { |v| money_to_d(v).is_a?(Numeric) }

        sorted =
          if numeric
            # 空单元格（无数量/无单价）排在末位
            rows.sort_by { |r| money_to_d(row_value(r, sym, col)) || Float::INFINITY }
          else
            rows.sort_by { |r| row_value(r, sym, col).to_s }
          end

        dir == :desc ? sorted.reverse : sorted
      end

      # ⚠ 行哈希是**符号键**（ledger_records / consume_record_row / apply_row / cost_block 全是
      #   `{ time:, qty:, ... }`），而 order 里的 column 是字符串 ⇒ 取值必须符号化。
      #   否则 r[col] 恒为 nil、整列静默不排序，只剩 dir 在反转默认顺序 ——
      #   症状极具误导性：「点表头方向反了，且点哪一列都一样」。
      def row_value(row, sym, str_key)
        return nil unless row.respond_to?(:[])

        if row.respond_to?(:key?)
          return row[sym] if row.key?(sym)
          return row[str_key] if row.key?(str_key)
        end
        row[sym]
      end

      def blank_cell?(v)
        s = v.to_s.strip
        s.empty? || ['—', '-', '–'].include?(s)
      end

      def money_to_d(v)
        return nil if v.nil?

        s = v.to_s.gsub(/[^\d.]/, '')
        return nil if s.blank?

        s.to_d
      rescue StandardError
        nil
      end

      def paginate(rows, page, per_page)
        total = rows.size
        offset = (page - 1) * per_page
        slice = rows.slice(offset, per_page) || []
        {
          data: slice.map.with_index do |r, i|
            { id: (r[:id].presence || "row-#{i}").to_s, type: (r[:type].presence || 'rc_row').to_s, attributes: r }
          end,
          meta: {
            total_pages: total.zero? ? 1 : (total.to_f / per_page).ceil,
            total_count: total,
            filtered_count: total
          }
        }
      end
    end
  end
end
