# frozen_string_literal: true

# 到货验收的项目级策略（eln_ui_receipt_policies · REQ-RES-RECEIPT / ADR-0032）
#
# 一张表只回答一个问题：**本项目允不允许验货人验自己的申请单？**
# 「谁能验」不在这里 —— 那是 `eln_ui_project_approvers` 的 `receipt` 阶段名单。
# 两者是**两个问题**，故不合并（见迁移文件头的理由）。
#
# 🔴 阻断阈值**不在这里**：走模块级配置 `Scinote::ElnUi.receipt_pending_block_limit`
#   （与服务逾期的 `service_result_strike_limit` 同一处登记），保证「机制只有一份」。
module Scinote
  module ElnUi
    class ReceiptPolicy < ActiveRecord::Base
      self.table_name = 'eln_ui_receipt_policies'

      belongs_to :project,    class_name: '::Project', inverse_of: false
      belongs_to :updated_by, class_name: '::User',    optional: true, inverse_of: false

      validates :project_id, uniqueness: true

      # 取该项目的策略；**没有行就是默认策略**（不允许自验）——
      # ⚠ 这里返回新对象而不是 nil，是为了让调用方写 `policy.allow_self_verification?`
      #   而不必处处判空。默认 false = fail-closed：没显式开就是不许自验。
      def self.for_project(project)
        pid = project.is_a?(::Project) ? project.id : project
        find_by(project_id: pid) || new(project_id: pid, allow_self_verification: false)
      end

      def allow_self_verification?
        !!allow_self_verification
      end

      # 幂等写入（配置面板保存用）。⚠ 不做「改了留历史版本」——
      #   策略是当前态不是流水，与审批人名单同语义（名单改动也不留版本）。
      def self.set_allow_self_verification!(project:, value:, updated_by: nil)
        pid = project.is_a?(::Project) ? project.id : project
        rec = find_or_initialize_by(project_id: pid)
        rec.allow_self_verification = !!value
        rec.updated_by = updated_by
        rec.save!
        rec
      end
    end
  end
end
