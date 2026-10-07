# frozen_string_literal: true

# 到货验收记录（eln_ui_receipt_verifications · REQ-RES-RECEIPT / ADR-0032）
#
# 一句话：**这张表是「这一批料到底验了没有、谁验的、验了多少」的答案来源。**
# 一次请购可分多批到货（SCN-RES-RECEIPT-3），故验收是**一对多**事实。
#
# ⚠ 三条与 eln_ui 其它 model 同源的铁律：
#   · 表名显式 self.table_name；
#   · class_name 一律带 `::`（避开宿主 Scinote::Project / Scinote::User 常量遮蔽）；
#   · 类体裹在 module Scinote::ElnUi 里（engine eager load 路径）。
#
# ⚠ status 不用 Rails enum：宿主在 string 列上用 enum 会把值序列化成整数下标再 cast
#   回字符串（ConsumeRecord#kind 实测踩过：kind_for_database => "0"，谓词恒 false）。
module Scinote
  module ElnUi
    class ReceiptVerification < ActiveRecord::Base
      self.table_name = 'eln_ui_receipt_verifications'

      # 到货照片（SCN-RES-RECEIPT-1：挂在**验收记录**上，分批时照片不串用）。
      # 用宿主 ActiveStorage，不自建文件表；先例：form_repository_rows_field_value.rb:19。
      # ⚠ 只声明、不在这里做上传策略 —— 附件权限与清理沿用宿主既有逻辑。
      has_many_attached :photos

      belongs_to :resource_application, class_name: '::Scinote::ElnUi::ResourceApplication',
                                          inverse_of: false
      belongs_to :verifier,   class_name: '::User', optional: true, inverse_of: false
      belongs_to :created_by, class_name: '::User', optional: true, inverse_of: false

      STATUSES = %w[pending passed rejected].freeze

      validates :status, inclusion: { in: STATUSES }
      # ⚠ qty 允许 0（建记录时可能先不填），但「通过」之前必须为正 —— 校验放在
      #   passed 动作里做，不在 validates 里，否则 pending 行会因 qty=0 存不进去。
      validates :qty, numericality: { greater_than_or_equal_to: 0 }

      scope :for_application, ->(app) { where(resource_application_id: app.is_a?(::Scinote::ElnUi::ResourceApplication) ? app.id : app) }
      scope :passed,  -> { where(status: 'passed') }
      scope :pending, -> { where(status: 'pending') }

      def pending?  = status == 'pending'
      def passed?   = status == 'passed'
      def rejected? = status == 'rejected'

      # 本表当前是否还有「已交照片但没人验」的悬空记录。
      # ⚠ 与「本单是否未验货」不是一回事：后者看**累计数量**（见 ReceiptVerification.verified_qty），
      #   因为分批场景下「验过一批、还有两批没到」也算未验货。
      def self.open_for(app)
        for_application(app).pending.order(:created_at)
      end

      # 累计**已通过**的验货数量（SCN-RES-RECEIPT-3 的收口判据）。
      # ⚠ 只算 passed：rejected 与 pending 都不算「已验」。
      def self.verified_qty(app)
        for_application(app).passed.sum(:qty).to_d
      end

      # 申请单申报的总量（申请量在草稿期可改，故每次实时读，不快照）
      def self.applied_qty(app)
        item = app.item_list.first
        return 0.to_d if item.blank?

        (item['qty'] || item[:qty]).to_d
      end

      # 「累计已验 ≥ 申请量」⇒ 本单收口为已完成（ADR-0032 的收口规则：库房数字说话，
      # 不引入「这是最后一批吗」这种易漏的勾选）。
      def self.completed_threshold_reached?(app)
        verified_qty(app) >= applied_qty(app)
      end

      # 详情页展示用的一行文案
      def status_label
        { 'pending' => '待验货', 'passed' => '已验货入库', 'rejected' => '验货不通过' }[status] || status
      end
    end
  end
end
