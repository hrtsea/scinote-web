# frozen_string_literal: true

# D3 钩子：Experiment#after_save 自动给 creator 加 experiment_owner manual UA。
#
# 根因：assignable.rb:147-148 让 top-level (Project/Team/Repository/Protocol/Form) 自动赋 Owner
# 给 creator，但 Experiment/MyModule 不在 TOP_LEVEL_ASSIGNABLES 里。若父级项目只有
# self_only_researcher UA，creator 在自己建的 Experiment 上仍只能继承父级角色，experiment_read
# 都没有。本钩子保证 creator 在自建 Experiment 上总能有 manage 级手动 UA。
#
# 不需要为 MyModule 注册：本 addon 只覆盖 top-level；MyModule 的 UA 由 native
# create_user_assignments! (assignable.rb:150-152 父级 UA 继承) 自然处理。
# 在 MyModule 上重复 D3 会与 native 撞唯一索引 (assignable_type, assignable_id, user_id, team_id)。
#
# 幂等/升级语义（D9.7 修正）：
#   旧判据是「creator 在这一层有没有任意 UA 行」，但 native create_user_assignments! 和
#   InheritUserAssignmentsJob 会先把 Project 上 creator 的 Owner 行原样复制到 Experiment，
#   于是「有任意 UA 行」几乎恒真 → D3 永远跳过，creator 拿不到 experiment_owner 手动行，
#    creator 的保护完全依赖父级自动行（父级角色一改，子对象跟着变）。
#   现判据：只认「experiment_owner 手动行」；已有行若不含 experiment_manage 则就地升级，
#   与 MyModule D3 的升级语义保持一致（同一 (assignable,user,team) 唯一行，update 不撞索引）。
#
# 角色软依赖：experiment_owner 角色不存在则静默跳过（D6 全角色未部署时回退到默认行为）。

module Scinote
  module AccessControl
    module ExperimentVisibility
      private

      def add_creator_experiment_owner_assignment!
        return if skip_access_control_visibility
        return unless Scinote::AccessControl.enabled?

        creator_id = created_by_id
        return if creator_id.blank?

        role = UserRole.find_by(name: 'experiment_owner', predefined: false)
        return if role.nil?

        team_id_value = project&.team_id
        return if team_id_value.blank?

        # 判据按 (user, team) 找，不能带 user_role_id：唯一索引是
        # (assignable_type, assignable_id, user_id, team_id)，角色不在里面。
        # 父级复制下来的 Owner automatically 行已经占了这个坑，再 create! 必撞
        # "User has already been taken" —— 所以只能就地升级。
        existing = user_assignments.find_by(user_id: creator_id, team_id: team_id_value)

        if existing
          # 已是手动行（native/人工给的更高权限，如 Owner manually）→ 不夺权
          return if existing.manually_assigned?

          existing.update!(user_role: role, assigned: :manually, assigned_by_id: creator_id)
        else
          user_assignments.create!(
            user_id: creator_id,
            user_role: role,
            assigned: :manually,
            assigned_by_id: creator_id,
            team_id: team_id_value
          )
        end
      end
    end
  end
end

unless Experiment.instance_variable_get(:@access_control_loaded)
  Experiment.instance_variable_set(:@access_control_loaded, true)

  Experiment.class_eval do
    attr_accessor :skip_access_control_visibility
  end

  # set_callback(:save, :after) 而非 :create, :after ——save 阶段确保 assignable.rb:145 native
  # create_user_assignments! 已先于本钩子执行完（top-level 分支赋 Owner）。本钩子在已有 UA
  # 时幂等跳过，无 UA 时补 experiment_owner manual UA。
  Experiment.set_callback(:save, :after, :add_creator_experiment_owner_assignment!)

  unless Experiment.method_defined?(:add_creator_experiment_owner_assignment!)
    Experiment.prepend(Scinote::AccessControl::ExperimentVisibility)
  end
end