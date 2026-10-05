# frozen_string_literal: true

# D2 —— 「默认继承 vs 默认隔离」项目级开关
#
# 为什么必须在这里拦：
#   InheritUserAssignmentsJob 是**异步**的。若只在 Experiment#after_create 里删行，
#   job 后跑会把行重新复制回来（实测：同步跑一次 job 后，成员立刻出现在新实验上）。
#   所以唯一可靠的拦截点是 job 自己 —— patch assign_to_experiment。
#
# 实测钉死的两条原生事实（决定了这段代码怎么写）：
#   1. 原生 User 角色本身就含 experiment_read，所以「成员被复制进实验」=「成员立刻可见」。
#   2. manually 行天然免疫该 job（inherit_user_assignments_job.rb:96 return if manually_assigned?），
#      所以 PI 在矩阵里勾过的格子**不会**被新建实验的复制逻辑冲掉。
#      → 本开关只影响「新建实验的默认值」，不影响已经放行的格子。
#
# 隔离模式下仍然保留谁：
#   - 项目管理者（角色含 project_manage：Owner / project_head）—— 否则 PI 和 Owner 自己也看不见
#   - 项目负责人 supervised_by_id
#   - 实验创建者 created_by（D3 会给他建 manually 锚点，这里兜底）
#   其余普通成员一律不复制 → 由 PI 在可见性矩阵里逐格放行。
#
# 组指派 / 团队指派在隔离模式下整体跳过：它们是「一批人一起可见」的通道，
# 一旦放行就等于回到继承模式，隔离失去意义。

module Scinote
  module AccessControl
    module VisibilityStrategy
      # 隔离模式下允许被复制进新实验的 user_id
      def ac_isolation_allowed_user_ids(project, experiment = nil)
        ids = []

        ids << project.supervised_by_id if project.respond_to?(:supervised_by_id) && project.supervised_by_id
        ids << experiment.created_by_id if experiment&.respond_to?(:created_by_id) && experiment.created_by_id

        project.user_assignments.includes(:user_role).find_each do |ua|
          ids << ua.user_id if ua.user_role&.permissions&.include?('project_manage')
        end

        ids.compact.uniq
      end

      private

      def assign_to_experiment(experiment)
        return super unless Scinote::AccessControl.enabled?

        project = experiment.project
        return super if project.nil?
        return super unless project.respond_to?(:isolated?)
        return super unless project.isolated?

        allowed = ac_isolation_allowed_user_ids(project, experiment)

        project.user_assignments.find_each do |assignment|
          next unless allowed.include?(assignment.user_id)

          create_or_update_assignment(assignment, experiment)
        end

        # 组 / 团队指派：隔离模式下不放行（见文件头说明）
        Rails.logger.info "[access_control] isolated project ##{project.id}: " \
                          "skipped group/team inheritance for experiment ##{experiment.id}"
      end
    end
  end
end

unless Project.instance_variable_get(:@access_control_strategy_loaded)
  Project.instance_variable_set(:@access_control_strategy_loaded, true)

  # 不加 prefix：想用的是 Project#isolated? / Project#inherit? 这种短名。
  # （若以后撞了宿主方法再加 prefix，目前 Project 上无同名方法。）
  Project.class_eval do
    enum :experiment_visibility_strategy, { inherit: 0, isolated: 1 }
  end

  unless UserAssignments::InheritUserAssignmentsJob
                                          .ancestors
                                          .include?(Scinote::AccessControl::VisibilityStrategy)
    UserAssignments::InheritUserAssignmentsJob.prepend(Scinote::AccessControl::VisibilityStrategy)
  end
end
