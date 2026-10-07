# frozen_string_literal: true

# ELN UI —— 消耗/执行明细导出（报告 §5 第 6 项 #12 · spec REQ-RES-CONSUME 末段）
#
# 规格要求明细表支持「按类型 / 项目 / 用户 / 时间范围筛选 + 导出」。
# 筛选在 ResCenterPayload 完成（与 consume 页签同源），本服务只负责把过滤后的
# 明细行渲染成 CSV（UTF-8 BOM，Excel 中文不乱码）。不造新数据源，纯渲染。
require 'csv'

module Scinote
  module ElnUi
    class ConsumeCsvExport
      HEADERS = %w[时间 类型 名称 数量 单价 金额 项目 操作人 状态].freeze

      def self.generate(records)
        csv = CSV.generate(headers: true, encoding: 'UTF-8') do |row|
          row << HEADERS
          records.each do |cr|
            row << [
              cr.occurred_at&.strftime('%Y-%m-%d %H:%M'),
              cr.kind == 'service' ? '服务' : '物资',
              cr.name.to_s,
              "#{cr.quantity} #{cr.unit}".strip,
              "¥#{cr.unit_price}",
              "¥#{cr.amount}",
              cr.project&.name.to_s,
              cr.user ? (cr.user.full_name.presence || cr.user.email.to_s) : '',
              cr.material? ? '—' : (cr.settled? ? '已结算' : '待验收')
            ]
          end
        end
        "\uFEFF#{csv}"
      end
    end
  end
end
