# frozen_string_literal: true

# 资源申请单（eln_ui_resource_applications）
#
# 业务语义见迁移文件 SCN-RES-APPROVE-1~5。这里只做 ORM 形状 + 状态机 +
# items JSON 的便利访问，不在这里写校验/审批流（属于 service 层）。
#
# ⚠ class_name 一律带 `::`（避开宿主 Scinote::User / Scinote::Project 常量遮蔽，
#   与 model 铁律 #10 同源坑）。
# ⚠ 表名显式 self.table_name，否则 Rails 推不出 eln_ui_resource_application → 单复数歧义。
module Scinote
  module ElnUi
    class ResourceApplication < ActiveRecord::Base
      self.table_name = 'eln_ui_resource_applications'

      # ---- 关联 ----
      belongs_to :project,         class_name: '::Project', inverse_of: false
      belongs_to :requestor,       class_name: '::User',   inverse_of: false
      belongs_to :group_reviewer,  class_name: '::User',   optional: true, inverse_of: false
      belongs_to :project_reviewer, class_name: '::User',  optional: true, inverse_of: false

      # ---- 状态枚举（迁移里 default 'draft'）----
      STATUSES = %w[
        draft
        submitted
        group_approved
        project_approved
        rejected
        completed
      ].freeze
      validates :status, inclusion: { in: STATUSES }

      # ---- 业务编号格式校验：SQ-YYYY-NNNN ----
      validates :no, presence: true,
                     format: { with: /\ASQ-\d{4}-\d{4}\z/,
                               message: 'must match SQ-YYYY-NNNN' }

      # ---- items JSON 便利访问 ----
      # 读：始终返回 Array（DB 里可能 null/缺省）
      #
      # 🔴 2026-10-05 真 bug：这里原本是 symbolize_keys，而写侧（下面）是 stringify_keys
      #    —— 写进 jsonb 的是字符串键，读回来却被转成符号键，消费端无论用哪一种键都不稳：
      #    只写字符串键的取值点（res_center_payload 的 ['name'] / ['unit']）直接取到 nil，
      #    列表里「材料 · 」后面是空的（生产库实测 item_list.first['name'] == nil）。
      #    改成 with_indifferent_access：与写侧对称，'name' / :name 两种写法都通，
      #    既补上漏的取值点，也不动消费端已有的 `it['x'] || it[:x]` 防御写法。
      def item_list
        (items || []).map(&:with_indifferent_access)
      end

      # 写：覆盖 items 列
      def item_list=(arr)
        self.items = Array(arr).map(&:stringify_keys)
      end

      # ---- 状态机查询谓词（service 层用，view 层不用）----
      def draft?;            status == 'draft';            end
      def submitted?;        status == 'submitted';        end
      def group_approved?;   status == 'group_approved';   end
      def project_approved?; status == 'project_approved'; end
      def rejected?;         status == 'rejected';         end
      def completed?;        status == 'completed';        end

      # 是否「进入审批流」 = 已提交 / 任一通过 / 已驳回 / 已完成
      def in_review?
        %w[submitted group_approved project_approved rejected].include?(status)
      end

      # 列表查询 scope
      scope :for_team, ->(team) {
        joins(:project).where(projects: { team_id: team.id })
      }
      scope :ordered, -> { order(submitted_at: :desc, id: :desc) }
    end
  end
end
