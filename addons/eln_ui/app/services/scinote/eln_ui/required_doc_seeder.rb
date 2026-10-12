# frozen_string_literal: true

# ELN UI —— 必传文档固定清单的补种器（ADR-0049 · REQ-PM-DOCS 固定清单化）
#
# 为什么需要它：必传文档 5 类（立项申请材料 / 项目任务书 / 年度计划 / 年度报告 /
# 结题报告）是**固定清单**（用户已撤回「负责人可增删」需求），但
# eln_ui_project_documents 是登记台账 —— 行是数据，不会凭空出现。
# 「已纳管」（有二开项目档案）是**事后状态**：ProjectProfile.upsert_for! 只在
# project_detail#update / update_status 里调，不是项目创建钩子 ⇒ 没有创建事件可挂，
# 补种只能挂在读路径上：controller#show 每次装配 payload 前调一次 seed!。
#
# 🔴 单真源分工：本常量只是**补种定义**，不是展示真源。页面渲染的永远是 DB 行
#   （ProjectDetailPayload#docs_block）—— 清单增减只改这里，页面自动跟上（D1）。
#   ⚠ 迁移里的补种是另一份**自含快照**（迁移不追随后端常量漂移），别把两者耦合成一处。
module Scinote
  module ElnUi
    class RequiredDocSeeder
      # 规范清单（定序即 position）。顺序 = 台账展示顺序（model scope :ordered
      # = order(:position, :id)），与前端文档面板历史上的 5 类枚举一一对应。
      REQUIRED_DOC_NAMES = %w[立项申请材料 项目任务书 年度计划 年度报告 结题报告].freeze

      class << self
        # 补种并返回**新建行数**（0 = 无需补种，或项目未纳管）。
        # 幂等：连续调用只有第一次建行，之后只做 position 归一。
        def seed!(project)
          return 0 unless managed?(project)

          new(project).seed!
        end

        # 「已纳管」判据 = 有二开项目档案行（eln_ui_project_profiles）。
        # 无档案的项目（从未进过 ELN 项目台账）不补种 —— 文档面板维持空态，
        # 不拿固定清单顶（D6：只补种给已纳管项目）。
        def managed?(project)
          Scinote::ElnUi::ProjectProfile.exists?(project_id: project.id)
        end
      end

      def initialize(project)
        @project = project
      end

      def seed!
        created = 0
        Scinote::ElnUi::ProjectDocument.transaction do
          REQUIRED_DOC_NAMES.each_with_index do |name, idx|
            doc = docs.find_or_initialize_by(category: 'required', name: name)
            doc.position = idx + 1
            created += 1 if doc.new_record?
            doc.save!
          end
        end
        created
      end

      private

      def docs
        Scinote::ElnUi::ProjectDocument.where(project_id: @project.id)
      end
    end
  end
end
