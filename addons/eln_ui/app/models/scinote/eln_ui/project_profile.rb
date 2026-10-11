# frozen_string_literal: true

# 项目级二开档案（eln_ui_project_profiles）—— 项目编号 / 项目来源 / 项目状态五态的承载面。
#
# ⚠ 与 eln_ui_task_profiles 同源的三条铁律：
#   · 表名显式 self.table_name；
#   · class_name 一律带 ::（避开宿主 Scinote::Project / Scinote::User 常量遮蔽）；
#   · 类体裹在 module Scinote::ElnUi 里（Zeitwerk eager load 路径；写成顶层类会让容器 boot exit 1）。
module Scinote
  module ElnUi
    class ProjectProfile < ActiveRecord::Base
      self.table_name = 'eln_ui_project_profiles'

      belongs_to :project, class_name: '::Project', inverse_of: false

      # 五态口径（REQ-PM-BASIC）。键用英文：中文落库会让排序与比较变得难以预测，
      # 展示文案走 STATUS_LABELS 单向映射（与 ReceiptVerification#status_label 同款做法）。
      STATUSES = %w[init running annual_review closing closed].freeze
      STATUS_LABELS = {
        'init' => '立项中',
        'running' => '执行中',
        'annual_review' => '年度考核',
        'closing' => '结题中',
        'closed' => '已结题'
      }.freeze

      validates :status, inclusion: { in: STATUSES }, allow_nil: true

      # 与 TaskProfile / ExperimentProfile 保持同一 API 形状（测试里已这么用）。
      def self.upsert_for!(project, attrs)
        find_or_initialize_by(project_id: project.id)
          .tap { |record| record.update!(attrs.merge(project: project)) }
      end

      def self.status_label(status)
        STATUS_LABELS[status] || status
      end

      def status_label
        self.class.status_label(status)
      end

      def closed?
        status == 'closed'
      end
    end
  end
end
