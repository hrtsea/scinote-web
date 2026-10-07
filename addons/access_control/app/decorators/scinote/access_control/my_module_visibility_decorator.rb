# frozen_string_literal: true

# D3 钩子：MyModule#after_save 保证 creator 在自建任务上有 task_owner 角色（task_* 管理权限）。
#
# 流程：
#   1. native create_user_assignments! (assignable.rb:150-152) 先于本钩子跑，根据父级
#      Experiment 的 UA 把 parent.user_role 复制到 MyModule。
#   2. 若父级 Experiment 上的 UA 是 experiment_owner（自己 D3 钩子创建的），native 会把
#      experiment_owner 角色复制到 MyModule——但 experiment_owner 没有 task_* 权限，
#      creator 看不到自己的任务。
#   3. 本钩子在 native 之后执行：
#      a. 若 MyModule 上 creator 已有 UA 且角色含 task_read → 跳过；
#      b. 若已有 UA 但角色不含 task_read → 升级 role 为 task_owner；
#      c. 若没有 UA（native 走 group/team 分支）→ 创建 task_owner manual UA。
#
# 不创建 task_* 缺失的角色，避免与 native 撞唯一索引 (assignable,user,team)。
# 角色软依赖：task_owner 角色不存在则静默跳过（D6 未部署时回退默认行为）。

module Scinote
  module AccessControl
    module MyModuleVisibility
      def self.prepended(base)
        base.include Scinote::AccessControl::AnchorAssignment

        # :save, :after 而不是 :create, :after —— save 在 create 之后，保证
        # native create_user_assignments! (assignable.rb:150-152) 先于本钩子跑完。
        base.after_save :add_creator_task_owner_assignment!
      end

      private

        def add_creator_task_owner_assignment!
          return unless Scinote::AccessControl.enabled?

          creator_id = created_by_id
          return if creator_id.blank?

          task_role = ac_role('task_owner')
          return if task_role.nil?

          team_id_value = ac_team_id_of(experiment&.project&.team_id)
          return if team_id_value.blank?

          # native 已建行就先看看够不够（含 task_read → 不动）；缺 task_* 就升级成 task_owner
          # （覆盖 experiment_owner 这类不带 task_* 的角色）。没有行才新建。
          existing = user_assignments.find_by(user_id: creator_id, team_id: team_id_value)
          return if (existing&.user_role&.permissions || []).include?('task_read')

          ac_anchor_row!(task_role, creator_id, team_id_value, assigned: :manually, assigned_by_id: creator_id)
        end
    end
  end
end

# 一行守卫就够：开发模式 to_prepare 走 load 会重跑本文件，不 return 就重复注册回调。
unless MyModule.instance_variable_get(:@access_control_loaded)
  MyModule.instance_variable_set(:@access_control_loaded, true)
  MyModule.prepend(Scinote::AccessControl::MyModuleVisibility)
end
