# frozen_string_literal: true

# D9.1 —— 可见性矩阵：PI 对「成员 × 实验」显式放行/收回（不落新表，直接写 Experiment 级 UA）
#
# 原 D9.5 设想建 ProjectVisibilityOverride 表 + 在 readable_by_user 里打补丁。
# 实测后改为复用原生 UA 机制，理由：
#   1. readable_by_user 是类方法返回 Relation（permission_checkable_model.rb:9-37），
#      在其上打补丁要同时改 Project/Experiment/MyModule 三条链，风险面大；
#   2. Experiment 级 UA 带 experiment_read 就已经让成员「可见」，无需新表；
#   3. manually 行天然免疫 InheritUserAssignmentsJob 异步覆盖（job:96 return if manually_assigned?），
#      撤回 = destroy 一行，恢复成本低。
#
# 语义（与词汇表 §6「可见壳」一致）：
#   - grant  → 成员看见这个 Experiment；其下 MyModule 仍逐任务判定（默认看不见）
#   - 想让成员连任务也看见，用 grant_member_visibility!(user, scope: :task) 给 task_owner
#   - revoke → destroy 本钩子造的那一行手动 UA（WL 角色），不动其他来源的 UA
#
# 返回值契约（UI 与 loop 脚本都依赖）：
#   grant   → true（调用后该成员对本 Experiment 可读）｜ false（未生效：插件关闭 / 角色缺失 / 用户空）
#   revoke  → :revoked（已删掉最后一行，成员不再可读）
#             :still_readable（手动行删了，但父级继承或其他角色仍让他可读 —— 界面要提示）
#             :noop（本来就没有可撤回的手动行）
#
# 幂等：连续 grant 两次只有第一次真正写库；连续 revoke 第二次返回 :noop。

module Scinote
  module AccessControl
    module VisibilityMatrix
      WL_ROLE_NAME = 'WL-实验可见(含画布)'
      # 任务级白名单：在 WL 基础上多一个 task_read。
      # 放在 Experiment 上 → experiment_read 让实验可见，task_read 同时充当「含任务」的持久化标记
      #   （job 的 create_or_update_assignment 会把父级行的 user_role 复制到子 MyModule，
      #    所以此后新建的任务会自动带上这个角色 → 放行一次、后续任务自动可见）；
      # 放在 MyModule 上 → task_read 让任务可见。一个角色两处复用。
      WL_TASK_ROLE_NAME = 'WL-实验+任务可见'
      TASK_ROLE_NAME = 'task_owner'

      # 出现在 UA 上是「系统给的」，不是「PI 勾的」—— 矩阵读数和 revoke 都要跳过
      AC_SYSTEM_ROLES = %w[experiment_owner project_head].freeze

      private

      def ac_wl_role
        @ac_wl_role ||= UserRole.find_by(name: WL_ROLE_NAME, predefined: false)
      end

      def ac_wl_task_role
        @ac_wl_task_role ||= UserRole.find_by(name: WL_TASK_ROLE_NAME, predefined: false)
      end

      def ac_task_role
        @ac_task_role ||= UserRole.find_by(name: TASK_ROLE_NAME, predefined: false)
      end

      # D9.1 —— 给成员在本 Experiment 上开「可见壳」。
      #
      # 升级语义（v2）：不能简单 `return if user_assignments.exists?(user:` 就跳过 ——
      # 原生 assignable.rb:147-152 与 InheritUserAssignmentsJob 会把 Project 上该成员的
      # Owner/自动行原样复制到 Experiment，「已经有一行」几乎恒真，会让 PI 勾选后毫无效果
      # （loop_pi_revoke.rb 首次跑就暴露了这个坑）。这里改成：找到 (user, team) 那一行，
      # 若其权限已能读本实验则不动，否则升级为 WL 角色；没有则新建。
      #
      # scope: :experiment（默认，实验 + 画布可见）| :task（实验 + 任务可见）
      #
      # 关键设计：**「PI 显式放行」与「角色权限」解耦**。
      # PI 勾一个格子时，成员多半已经因为「项目成员」被父级物化了一行普通角色 ——
      # 若此时直接 return（早期版本），界面上勾选框画完一刷新就变回虚框，PI 会以为系统坏了。
      # 所以：行已存在时**不降级角色**（降级会让 PI 丢掉 experiment_users_manage 之类权限），
      # 只把 assigned 翻成 manually —— manually 在 SciNote 里恰好就是「人工指定、不被自动机制覆盖」，
      # 正好表达「PI 显式放过这格」。行不存在（成员本来就看不到这实验）时才新建 WL 角色行。
      def grant_member_visibility!(user, scope: :experiment)
        return false if user.blank? || !Scinote::AccessControl.enabled?

        role = scope == :task ? ac_wl_task_role : ac_wl_role
        return false if role.nil?

        team_value = respond_to?(:team_id) ? team_id : project&.team_id
        return false if team_value.blank?

        ac_upsert_visibility_row!(self, user, role, team_value)

        # 任务可见性只存在于 MyModule 层：实验上那一行带不到任务上
        # （permission_granted? 只查对象自身 UA，permission_checkable_model.rb:49-65）。
        # 所以 scope=:task 必须逐个任务落行，否则 PI 勾了「含任务」成员还是看不见。
        if scope == :task
          my_modules.active.find_each do |mod|
            ac_upsert_visibility_row!(mod, user, role, team_value)
          end
        end

        true
      end

      # 在 target（Experiment 或 MyModule）上 upsert 一行可见性授权。
      # 升级语义，三种情形：
      #   - 无行          → 建 role 手动行
      #   - 有行且已能读  → 只翻 manually 标记，绝不降级角色（降级会丢 experiment_users_manage 等）
      #   - 有行但读不到  → 升级为 role（但系统锚点行除外 —— 那是 D3 给 creator 的，不能被 PI 顺手改掉）
      def ac_upsert_visibility_row!(target, user, role, team_value)
        row = target.user_assignments.find_by(user_id: user.id, team_id: team_value)
        needed = role.permissions.include?('task_read') ? 'task_read' : 'experiment_read'

        if row.nil?
          target.user_assignments.create!(
            user_id: user.id,
            user_role: role,
            assigned: :manually,
            assigned_by_id: user.id,
            team_id: team_value
          )
        elsif row.user_role.permissions.include?(needed)
          row.update!(assigned: :manually, assigned_by_id: user.id) unless row.manually_assigned?
        elsif AC_SYSTEM_ROLES.include?(row.user_role&.name)
          # creator 的 experiment_owner / PI 的 project_head：保留角色，只补手动标记
          row.update!(assigned: :manually, assigned_by_id: user.id) unless row.manually_assigned?
        else
          row.update!(user_role: role, assigned: :manually, assigned_by_id: user.id)
        end
      end

      # 撤回显式放行。分两类处理：
      #   - 纯放行行（WL 角色，唯一目的是「看得见」）→ destroy
      #   - 被顺手标成 manually 的更强角色行（如项目成员物化行）→ 把 assigned 打回 automatically，
      #     保留角色自带的权限，只撤掉「PI 显式放过」这个标记
      # 绝不按 user_id 一刀切 —— 那会连 D3 creator 锚点、PI 自己被显式放行的行一起抹掉。
      #
      # 返回值里的 :still_readable 很重要：PI 勾掉的格子未必真的生效（成员可能同时是
      # 项目 Owner / 该实验 creator）。界面据此提示「仍可通过 X 访问」，避免假阴性。
      def revoke_member_visibility!(user, scope: :experiment)
        return :noop if user.blank?

        role = scope == :task ? ac_wl_task_role : ac_wl_role
        return :noop if role.nil?

        return ac_revoke_task_visibility!(user, role) if scope == :task

        # 排除系统角色行：creator 的 experiment_owner（D3 锚点）和 PI 的 project_head
        # 都是 manually，但它们不是「PI 勾的可见性」，绝不能被 revoke 顺手改状态
        system_role_ids = UserRole.where(name: AC_SYSTEM_ROLES).pluck(:id)
        rows = user_assignments.where(user_id: user.id, assigned: :manually)
                               .where.not(user_role_id: system_role_ids)
        return :noop if rows.none?

        rows.each do |row|
          if row.user_role_id == role.id
            row.destroy!
          else
            row.update!(assigned: :automatically, assigned_by_id: nil)
          end
        end

        manual_left = user_assignments.where(user_id: user.id, assigned: :manually).exists?
        manual_left ? :still_readable : :revoked
      end

      # 收回「含任务」：撤掉任务可见性，但保留实验可见（PI 只是不想让人碰任务）。
      # 只认 WL+task 这一个角色的行 —— 绝不按 user_id 一刀切，否则会把
      # D3 给 creator 的 task_owner 锚点行一起删掉。
      def ac_revoke_task_visibility!(user, role)
        changed = false

        my_modules.find_each do |mod|
          rows = mod.user_assignments.where(user_id: user.id, user_role_id: role.id)
          next if rows.none?

          rows.destroy_all
          changed = true
        end

        # 实验上那条是「含任务」的标记行：降级回 WL，去掉 task_read 但保留实验可见。
        row = user_assignments.find_by(user_id: user.id, user_role_id: role.id)
        if row && ac_wl_role
          row.update!(user_role: ac_wl_role)
          changed = true
        end

        changed ? :revoked : :noop
      end

      def ac_manually_in?(user, permission)
        user_assignments
          .joins(:user_role)
          .where(user_id: user.id, assigned: :manually, user_roles: { permissions: permission })
          .exists?
      rescue StandardError
        # user_roles.permissions 是数组列，部分环境 join 条件写法不同；退化为 Ruby 侧判断
        user_assignments.where(user_id: user.id, assigned: :manually).any? do |row|
          row.user_role&.permissions&.include?(permission)
        end
      end

      # D9.4 矩阵读数：该成员对本 Experiment 是否被 PI 显式放过（画实心框的依据）。
      #
      # 判据 = manually 行 + 角色能读 + 角色不是「系统角色」。最后一条很关键：
      # D3 给 creator 建的 experiment_owner 手动行、PI 自己的 project_head 手动行，
      # 从矩阵视角是「系统自动给的创作/管理权」，不是「PI 勾的可见性」。
      # 不加这层过滤，PI 一打开矩阵就看到创建者的格子全实心，会以为自己之前勾过。
      def ac_manually_granted?(user, scope: :experiment)
        return false if user.blank?

        permission = scope == :task ? 'task_read' : 'experiment_read'

        user_assignments.where(user_id: user.id, assigned: :manually).any? do |row|
          role = row.user_role
          role.present? && !AC_SYSTEM_ROLES.include?(role.name) && role.permissions.include?(permission)
        end
      end
    end
  end
end

unless Experiment.instance_variable_get(:@access_control_matrix_loaded)
  Experiment.instance_variable_set(:@access_control_matrix_loaded, true)

  Experiment.prepend(Scinote::AccessControl::VisibilityMatrix)
end
