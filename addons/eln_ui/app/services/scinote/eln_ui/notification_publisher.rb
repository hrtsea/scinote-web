# frozen_string_literal: true

# ELN UI —— 极简通知发布器
#
# 报告 §5 第 4 项（#4）要求：通知中心触发源（驳回 / 审核 / 申请结果）要有落点，
# 「最小实现是 after_create_commit 触发原生 Notification 工厂，不用自造表」。
#
# 设计取舍（DHH 口径，只做最小必要的事）：
# - 用**原生 Notification 表**（GeneralNotification 类型），不造 addon 自有表 —— 满足「不用自造表」。
# - 不走 GeneralNotification.send_notifications 工厂方法：它内部按 params[:type]
#   去 NotificationExtends::NOTIFICATIONS_TYPES 查 recipients_module 再 constantize，
#   而 eln_ui 没在原生初始化器里注册类型（不碰 Rails 本体铁律），查不到 = Recipients::nil 崩溃；
#   且 notification_subgroup 对非注册 type 会 nil[0] 抛错。workbench_test 已验证
#   直接 Notification.create!(type:'GeneralNotification', recipient:, params:) 是稳定范式。
# - 收件人显式传入（审批人/申请人本来就在流程里已知），所以也不需要 Recipients::* 解析。
# - 通知是副作用：发布失败只 warn，绝不回滚主流程（提交/审批比「没通知」重要得多）。
module Scinote
  module ElnUi
    class NotificationPublisher
      # recipient: User 实例或 id；subject: 被引用的业务对象（点击通知跳转用，可选）
      def self.notify(recipient, title:, message:, subject: nil)
        user = recipient.is_a?(::User) ? recipient : ::User.find_by(id: recipient)
        return nil if user.nil?

        params = { title: title, message: message }
        if subject
          params[:subject_id]    = subject.id
          params[:subject_class] = subject.class.name
          params[:subject_name]  = subject.respond_to?(:name) ? subject.name : nil
        end

        ::Notification.create!(
          type: 'GeneralNotification',
          recipient: user,
          params: params
        )
      rescue StandardError => e
        Rails.logger&.warn("eln_ui NotificationPublisher failed: #{e.class}: #{e.message}")
        nil
      end

      # 取项目所有 predefined owner（用于「提交申请 → 通知待审人」）。
      # 取不到（表/角色缺失）→ 返回 []，由调用方决定 fail 方向（此处 fail-soft 不通知）。
      def self.project_owners(project)
        role = ::UserRole.find_predefined_owner_role
        return [] if role.nil? || !defined?(::UserAssignment) || !::UserAssignment.table_exists?

        ::UserAssignment
          .where(assignable_type: 'Project', assignable_id: project.id, user_role_id: role.id)
          .map(&:user)
          .compact
      rescue StandardError
        []
      end
    end
  end
end
