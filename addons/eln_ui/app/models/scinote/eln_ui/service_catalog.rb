# frozen_string_literal: true

# 测试表征服务档案条目（eln_ui_service_catalogs · REQ-RES-ARCHIVE）
#
# spec V1.21 L986 / L1051：服务**不建库存条目、不设 Stock 额度**，档案是服务目录的
# **唯一载体**，其 `unit_price` 是服务行登记时的快照来源；`requires_acceptance`
# 决定登记后落在「待验收」还是直接计入花费（L1010，默认 true）。
#
# ⚠ 与 eln_ui 其他 model 同源铁律：
#   · 表名显式 self.table_name；类体裹 module Scinote::ElnUi；class_name 带 `::`；
#     本表无外部关联，不涉常量遮蔽，但铁律照走。
module Scinote
  module ElnUi
    class ServiceCatalog < ActiveRecord::Base
      self.table_name = 'eln_ui_service_catalogs'

      # 登记服务行时取它的快照，别在调用处零散做 `.to_d`：
      #   · 金额一律 × 快照单价，
      #   · result_status 由它决定（见 ConsumeRecord.sync_service_from_application!）。
      def snapshot_price
        unit_price.to_d
      end

      def acceptance_required?
        requires_acceptance == true
      end
    end
  end
end
