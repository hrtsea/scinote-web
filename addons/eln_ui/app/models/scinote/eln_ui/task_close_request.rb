# frozen_string_literal: true

# 任务关闭审核单（eln_ui_task_close_requests · REQ-TASK-CLOSE）
#
# 一句话：**这张表就是「任务是否已关闭」的答案来源**。
# 原生 my_modules.state 装不下「待审核」这一档（见迁移注释），也不许改它，
# 于是「已关闭」= 这里有 approved 行；「待审核」= 有 pending 行。
#
# ⚠ 与 eln_ui 其他 model 同源铁律：显式 table_name + 类体裹 module Scinote::ElnUi +
#   class_name 带 `::`（否则 isolate_namespace 把它解析成 Scinote::ElnUi::MyModule）。
module Scinote
  module ElnUi
    class TaskCloseRequest < ActiveRecord::Base
      self.table_name = 'eln_ui_task_close_requests'

      # 状态枚举固定三档（SCN-TASK-CLOSE-1/4）。⚠ 不用 Rails enum：
      #   宿主在 string 列上用 enum 会把值序列化成整数下标再 cast 回字符串
      #   （ConsumeRecord 的 kind/result_status 已实测踩过，17F+6E）。
      STATES = %w[pending approved rejected].freeze
      STATE_LABELS = { 'pending' => '待审核', 'approved' => '已关闭', 'rejected' => '已驳回' }.freeze

      belongs_to :my_module,    class_name: '::MyModule', inverse_of: false
      belongs_to :submitted_by, class_name: '::User',     inverse_of: false
      belongs_to :reviewer,     class_name: '::User',     inverse_of: false, optional: true

      validates :status, inclusion: { in: STATES }
      validates :submitted_at, presence: true
      # SCN-TASK-CLOSE-4：驳回必须给理由，通过/待审核不要求。
      validate :rejection_needs_reason

      scope :pending,   -> { where(status: 'pending') }
      scope :approved,  -> { where(status: 'approved') }
      scope :rejected,  -> { where(status: 'rejected') }

      def self.state_labels = STATE_LABELS

      # 当前态看**最新一行**：驳回后重新提交会产生第二行，只看 pending 会漏掉历史。
      def self.latest_for(my_module)
        where(my_module_id: my_module.id).order(submitted_at: :desc, id: :desc).first
      end

      def self.pending_for(my_module)
        pending.where(my_module_id: my_module.id).order(submitted_at: :desc).first
      end

      # 已关闭 = 有 approved 行（一旦通过就不再退回，除非将来另开「重开」需求）
      def self.closed?(my_module)
        approved.where(my_module_id: my_module.id).exists?
      end

      def pending?   = status == 'pending'
      def approved?  = status == 'approved'
      def rejected?  = status == 'rejected'
      def state_label = STATE_LABELS[status] || status

      private

      def rejection_needs_reason
        return unless rejected?
        return if reason.present?

        errors.add(:reason, '驳回关闭申请必须填写驳回理由（SCN-TASK-CLOSE-4）')
      end
    end
  end
end
