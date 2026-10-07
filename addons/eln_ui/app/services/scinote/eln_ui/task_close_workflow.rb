# frozen_string_literal: true

# ELN UI —— 任务关闭审核流程（REQ-TASK-CLOSE / SCN-TASK-CLOSE-1..4 · DEC-003）
#
# 规格：
#   L771「实验任务标记『已关闭』必须且只能由**项目负责人**审核通过触发。组员不可关闭
#        任务；小组组长可新建/指派任务但不可审核关闭。」
#   L775 SCN-TASK-CLOSE-1 待审核 + 项目负责人通过 → 已关闭
#   L780 SCN-TASK-CLOSE-2 组员不提供关闭/审核关闭入口
#   L784 SCN-TASK-CLOSE-3 小组组长不提供审核关闭入口
#   L788 SCN-TASK-CLOSE-4 驳回**必须**填理由，任务退回前序状态
#
# 骨架（白名单 / 分派 / gate! / WorkflowError→422）来自 Scinote::ElnUi::Workflow，
# 与资源申请单共用 —— 两条流程的骨架一样，业务规则各自留在本文件。
#
# ⚠ 「项目负责人」的判定口径（这是本流程唯一有争议的地方，OPEN-1 未决前的取法）：
#   取**宿主原生**的项目 owner 角色（UserAssignment on Project 持 predefined owner role）。
#   为什么不用 eln_ui_task_profiles.owner_user：那是任务级「显式负责人」（PRD §7.8.2 展示用），
#   拿它当审核权 = 谁被指派谁就能关自己的任务，spec 明写要项目负责人审。
#   为什么不用 addon 自己的角色表：会与宿主 ACL 变成两套真相。
#   取不到判定（表不存在等）→ **fail-closed 当成非负责人**：宁可没人能审，
#   也不能「判不出来就放行」。
module Scinote
  module ElnUi
    class TaskCloseWorkflow < Workflow
      WorkflowError = Scinote::ElnUi::Workflow::WorkflowError

      ACTIONS = %w[submit approve reject].freeze

      class << self
        def actions
          ACTIONS
        end

        def call(user:, team:, my_module_id:, type:, reason: nil)
          my_module = ::MyModule.find_by(id: my_module_id)
          raise WorkflowError, '任务不存在或已归档' if my_module.nil?

          new(my_module: my_module, user: user, team: team).run(type.to_s, reason.to_s.presence)
        end

        # 这个人能不能审核关闭（前端入口也读它 —— 判一处，别在页面和后端各判一次）
        def reviewer?(user, my_module)
          return false if user.blank? || my_module.blank?

          owner_role = ::UserRole.find_predefined_owner_role
          return false if owner_role.nil?
          return false unless defined?(::UserAssignment) && ::UserAssignment.table_exists?

          ::UserAssignment.exists?(
            assignable_type: 'Project', assignable_id: project_id_of(my_module),
            user_id: user.id, user_role_id: owner_role.id
          )
        end

        def project_id_of(my_module)
          my_module.experiment&.project_id
        end
      end

      def initialize(my_module:, user:, team:)
        @my_module = my_module
        super(user: user, team: team)
      end

      private

      attr_reader :my_module

      def result_payload
        { ok: true, state: current_state, stateLabel: current_state_label,
          myModuleId: my_module.id }
      end

      # ---- 动作 ----

      # 提交完成申请：同团队成员即可提交（谁在干这个活谁就能提）。
      # ⚠ 刻意**不**要求项目负责人 —— spec 只约束「审核关闭」这一侧（SCN-TASK-CLOSE-1
      #   的触发条件是「任务处于待审核且项目负责人通过」），把提交也卡给负责人
      #   会让组员连「我干完了」都报不上去。
      def apply_submit(_reason)
        gate!(same_team?, '仅同团队成员可提交完成申请')
        gate!(!TaskCloseRequest.closed?(my_module), '该任务已关闭，无需再次提交')
        gate!(TaskCloseRequest.pending_for(my_module).nil?, '该任务已有待审核的关闭申请')

        TaskCloseRequest.create!(
          my_module: my_module, status: 'pending', submitted_by: @user,
          submitted_at: Time.current
        )
      end

      def apply_approve(_reason)
        gate_reviewer!
        request = pending_request!
        request.update!(status: 'approved', reviewer: @user, reviewed_at: Time.current)
        notify_submitter(request, approved: true)
      end

      # SCN-TASK-CLOSE-4：驳回必填理由 —— 「退回前序状态」在本表里的体现是
      # 这一行走 rejected、任务不被标记关闭；下次提交会新起一行，历史留痕。
      def apply_reject(reason)
        gate_reviewer!
        gate!(reason.present?, '驳回关闭申请必须填写驳回理由')
        request = pending_request!
        request.update!(status: 'rejected', reviewer: @user,
                         reviewed_at: Time.current, reason: reason)
        notify_submitter(request, approved: false, reason: reason)
      end

      # SCN-TASK-CLOSE-4「通知提交人」：审核结论（通过 / 驳回）一律通知申请提交方。
      # 通知是副作用，发布失败不影响审核结果落库（见 NotificationPublisher 的 fail-soft）。
      def notify_submitter(request, approved:, reason: nil)
        task = request.my_module
        title = approved ? '任务关闭申请已通过' : '任务关闭申请被驳回'
        msg = if approved
                "任务「#{task&.name}」的关闭申请已由 #{@user.name} 审核通过。"
              else
                "任务「#{task&.name}」的关闭申请被驳回#{reason.present? ? '：' + reason : ''}。"
              end
        Scinote::ElnUi::NotificationPublisher.notify(
          request.submitted_by, title: title, message: msg, subject: task
        )
      end

      # ---- 闸门 ----

      def gate_reviewer!
        gate!(self.class.reviewer?(@user, my_module),
              '仅项目负责人可审核关闭任务（SCN-TASK-CLOSE-2/3）')
      end

      def pending_request!
        request = TaskCloseRequest.pending_for(my_module)
        raise WorkflowError, '该任务没有待审核的关闭申请' if request.nil?

        request
      end

      def same_team?
        team.present? && my_module.experiment&.project&.team_id == team.id
      end

      def current_request
        @current_request ||= TaskCloseRequest.latest_for(my_module)
      end

      def current_state
        current_request&.status || 'none'
      end

      def current_state_label
        TaskCloseRequest::STATE_LABELS[current_state] || '未提交关闭申请'
      end
    end
  end
end
