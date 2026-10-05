# frozen_string_literal: true

# D9.2 —— Project#supervised_by_id 变更时同步 PI 权限（项目负责人 = 能管项目权限 + 成员可见性）
#
# 根因：SciNote 原生 supervised_by_id（head of project）是纯元数据。projects_controller.rb:133-135
#       在变更时只写活动流（remove_head_of_project 377 / set_head_of_project 378），
#       「head」拿不到任何权限位点。用户反馈「head_of_project 那看起来作用很小」。
#
# 本钩子：把「设 head」和「给 head 权限」接起来。
#   - 新 head：upsert 一条 manually UA 在 Project 上，角色 project_head（D9 build 脚本建）
#             并跑一次 PropagateAssignmentJob(destroy: false)，让新 PI 立刻拿到
#             「项目下全部实验 + 任务」的 automatically 基线行（等价于异步 worker 行为）
#   - 旧 head：撤回本钩子此前创建的那一类行（role=project_head 且 manually），
#              并用 PropagateAssignmentJob(destroy: true) **递归收回**旧 PI 已在
#             Experiment/MyModule 上物化的 automatically 行（D9.7 缺口）。
#             只撤这一类行，避免误删 Owner/组指派/团队指派来的 UA。
#
# 幂等：supervised_by_id 未变 → 直接 return；已有 project_head UA → 不重复建。
# 角色软依赖：project_head 角色不存在则静默跳过（D6 全角色未部署时回退原生行为）。
# 与 D3 的差别：D3 补 Experiment creator，本钩子补 Project head，两者互不干涉。
#
# 为什么必须走 PropagateAssignmentJob 而不是 destroy_all：
#   permission_granted? 只查对象自身 UA，父级权限不向上走 → 旧 PI 的 Project 行删了，
#   他在 exp/task 上的 automatically 行还挂着，仍然读得到。只能靠递归物化回收。

module Scinote
  module AccessControl
    module ProjectHeadVisibility
      private

      def ac_head_role
        @ac_head_role ||= UserRole.find_by(name: 'project_head', predefined: false)
      end

      # 供 D9.1 与测试脚本读取，避免每处再查一次
      def ac_head_role_id
        ac_head_role&.id
      end

      def sync_project_head_assignment!
        return if skip_access_control_visibility
        return unless Scinote::AccessControl.enabled?

        role = ac_head_role
        return if role.nil?

        changes = saved_changes[:supervised_by_id]
        return if changes.blank?

        old_id, new_id = changes

        # 1) 新 head：升级已有 UA 或新建（升级语义避开 (assignable,user,team) 唯一索引冲突）
        head_row = grant_project_head_assignment(new_id, role) if new_id.present?

        # 1b) 新 PI 立即拿到子对象基线可见性（与异步 worker 同一条路径）
        propagate_head_assignment!(head_row, new_id) if head_row.present?

        # 2) 旧 head：撤本钩子造的那一行 + 递归收回子对象上的物化行
        if old_id.present? && old_id != new_id
          revoke_project_head_assignment(old_id, role, assigner_id: new_id)
        end
      end

      def grant_project_head_assignment(user_id, role)
        return if user_id.blank?

        team_value = respond_to?(:team_id) ? team_id : nil
        return if team_value.blank?

        row = user_assignments.find_by(user_id: user_id, team_id: team_value)
        if row
          # 已有 UA：若权限不足则升级为 project_head（保留 manually 语义）
          return row if row.user_role_id == role.id
          return row if row.user_role.permissions.include?('project_manage')

          row.update!(user_role: role)
          row
        else
          user_assignments.create!(
            user_id: user_id,
            user_role: role,
            assigned: :manually,
            assigned_by_id: user_id,
            team_id: team_value
          )
        end
      end

      # 新 PI 权限下放到 Experiment/MyModule（destroy: false 走 create_or_update_assignment）
      def propagate_head_assignment!(row, assigner_id)
        return if row.blank? || assigner_id.blank?

        UserAssignments::PropagateAssignmentJob.perform_now(row, assigner_id: assigner_id, destroy: false)
      rescue StandardError => e
        Rails.logger.warn "[access_control] head propagate failed: #{e.class}: #{e.message}"
      end

      # D9.7 —— 旧 PI 转移后，递归收回他在子对象上物化的 automatically 行。
      # 只认 role=project_head 且 manually 的那一行；子对象上的行按 user_id 匹配删（原生动词）。
      def revoke_project_head_assignment(user_id, role, assigner_id: nil)
        return if user_id.blank?

        row = user_assignments.find_by(user_id: user_id, user_role_id: role.id, assigned: :manually)
        return if row.nil?

        # 只删 Project 上「本钩子造的那一行」（role=project_head 且 manually）
        row.destroy!

        revoke_head_descendant_assignments!(user_id)
      rescue StandardError => e
        Rails.logger.warn "[access_control] head revoke failed: #{e.class}: #{e.message}"
      end

      # 只回收「自动物化」的子对象行，保留同一用户在子对象上的 manually 行。
      #
      # 为什么不用原生 PropagateAssignmentJob(destroy: true)：
      #   它的 destroy_assignment 按 user_id 删，不区分 assigned 语义 —— 会把同一用户在
      #   子对象上的**手动授权**（可见性矩阵 D9.1 显式放行、D3 creator 锚点）一并删掉。
      #   实测踩到：PI 从 hrtsea 转到 admin 时，admin 此前被 PI 显式放行的 exp2 手动行
      #   也被回收，async 传播后 admin 直接读不到 exp2（loop_pi.rb Phase 6 两条 FAIL）。
      #   manually 在 SciNote 的语义里就是「人工指定、不被自动机制覆盖」（见 job:96），
      #   身份变更不该静默撤销人工授权；旧 PI 若还留着手动行，他仍应能读。
      #
      # 覆盖面：Experiment + MyModule 两层递归，与原生 job 的 sync_resource_user_associations 同深。
      def revoke_head_descendant_assignments!(user_id)
        return if user_id.blank?

        experiments.each do |exp|
          exp.user_assignments.where(user_id: user_id, assigned: :automatically).destroy_all

          exp.my_modules.each do |task|
            task.user_assignments.where(user_id: user_id, assigned: :automatically).destroy_all
          end
        end
      end
    end
  end
end

unless Project.instance_variable_get(:@access_control_head_loaded)
  Project.instance_variable_set(:@access_control_head_loaded, true)

  Project.class_eval do
    attr_accessor :skip_access_control_visibility
  end

  # 与 D3 同为 :save, :after —— native assignable.rb:145 的 after_create create_user_assignments!
  # 对 top-level Project 走「手动加 Owner」分支，本钩子在其后跑，可以安全升级/新建。
  Project.set_callback(:save, :after, :sync_project_head_assignment!)

  unless Project.method_defined?(:sync_project_head_assignment!)
    Project.prepend(Scinote::AccessControl::ProjectHeadVisibility)
  end
end
