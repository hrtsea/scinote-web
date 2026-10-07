# frozen_string_literal: true

# 项目级审批人（eln_ui_project_approvers · REQ-RES-APPROVER）
#
# 一句话：**这张表就是「谁有资格批这个项目的这一阶段」的答案来源**。
# 二段式审批（初审 group / 终审 project）的资格从此是显式的名单，
# 不再从「同团队 + 非本人」这种推断口径里推（详见迁移文件头注释）。
#
# ⚠ 与 eln_ui 其他 model 同源铁律：显式 table_name + 类体裹 module Scinote::ElnUi +
#   class_name 带 `::`（否则 isolate_namespace 把它解析成 Scinote::ElnUi::Project）。
#
# ⚠ stage 用 string + 白名单，**不用 Rails enum**：宿主在 string 列上用 enum 会把
#   值序列化成整数下标（TaskCloseRequest / ConsumeRecord 已实测踩过）。
module Scinote
  module ElnUi
    class ProjectApprover < ActiveRecord::Base
      self.table_name = 'eln_ui_project_approvers'

      STAGES = %w[group project receipt].freeze
      STAGE_LABELS = { 'group' => '初审', 'project' => '终审', 'receipt' => '验货' }.freeze

      belongs_to :project,    class_name: '::Project', inverse_of: false
      belongs_to :user,       class_name: '::User',    inverse_of: false
      belongs_to :created_by, class_name: '::User',    inverse_of: false, optional: true

      # ⚠ 阶段白名单是**代码内**的（不是 DB check 约束），所以新增 `receipt` 阶段时
      #   既有行不需要迁移；但**历史数据里不可能有 receipt 行**（此前阶段只有两个），
      #   于是老项目在配出验货人之前一律「无人可验」（fail-closed）——
      #   这与 SCN-RES-APPROVER 的纪律一致：没配名单 = 没人能批，不是「回退到宽口径」。
      validates :stage, inclusion: { in: STAGES }
      validates :user_id, uniqueness: { scope: %i[project_id stage] }

      scope :for_project, ->(project) { where(project_id: project.is_a?(::Project) ? project.id : project) }
      scope :for_stage,   ->(stage)   { where(stage: stage.to_s) }
      scope :for_user,    ->(user)    { where(user_id: user.is_a?(::User) ? user.id : user) }

      def self.stages = STAGES
      def self.stage_labels = STAGE_LABELS

      def self.users_for(project:, stage:)
        user_ids = for_project(project).for_stage(stage).pluck(:user_id)
        return [] if user_ids.empty?

        # 保持名单里的插入顺序（facilities 里按人排，不要按 id 排）
        ::User.where(id: user_ids).index_by(&:id).values_at(*user_ids).compact
      end

      # 幂等新增：已存在就返回原行（不做废后又建，避免唯一索引抖动）
      def self.add!(project:, user:, stage:, created_by: nil)
        for_project(project).for_stage(stage).for_user(user).first ||
          create!(project: project, user: user, stage: stage.to_s, created_by: created_by)
      end

      # 「我有没有被指定为某阶段的审批人」—— 只答名单本身，不含团队/本人等闸门
      def self.assigned?(project:, user:, stage:)
        return false if project.nil? || user.nil?

        for_project(project).for_stage(stage).for_user(user).exists?
      end

      def stage_label = STAGE_LABELS[stage] || stage.to_s
    end
  end
end
