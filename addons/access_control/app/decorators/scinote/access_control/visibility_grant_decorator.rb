# frozen_string_literal: true

# D9.1 —— 可见性矩阵里的**一格**：放行 / 收回（prepend 到 Experiment）
#
# 名字里为什么没有「矩阵」：这里只管一格的写侧，矩阵是 VisibilityMatrixService 读出来的
# 东西。同词两义曾经让两块都改不动 —— 读数想加个字段要来改这里，写侧想加个语义
# 又要去改那边。
#
# ## 「PI 勾过这一格」记在哪（2026-10-05 重构）
#
# 原来**没有落点**，只能从 UA 行上反推：
#   assigned == :manually + 角色名不在 [experiment_owner, project_head] + 角色含 experiment_read
# 反推是错的，不是精度问题而是语义问题：`assigned` 是**原生字段**，宿主后台的手工指派、
# 别的 addon 都在写它，「这一行是谁写的」不可知。于是 revoke 只能扫「user_id + manually
# + 非两个系统角色」，把剩下所有手动行一律打回 automatically —— 顺手撤掉**别的来源**
# 留给该成员的人工授权。而这里的注释当时还写着「绝不按 user_id 一刀切」。
#
# 现在这个事实记在 addon 自己的 `access_control_manual_grants`（ManualGrant）：
#   · grant  → 写 UA 行（可见性真正生效的地方，原生 permission_granted? 只认它）+ 记一行
#   · revoke → 查那一行；没有就 :noop，一行 UA 都不碰
#   · 读数  → 查那一行；三段推断全删
# 按项目铁律，addon 自己的事实落 addon 自有表（同 eln_ui_* 的做法），不借原生字段反推。
#
# ## 返回值契约（UI 与 loop 脚本都依赖，见 show.html.erb）
#
#   grant   → true（调用后该成员对本 Experiment 可读）｜ false（未生效：插件关 / 角色缺 / 用户空）
#   revoke  → :revoked（本 addon 放的行撤了，成员不再可读）
#             :still_readable（撤完了，但别的来源仍让他可读 —— 界面要提示，避免假阴性）
#             :noop（这一格本来就没有 PI 的放行记录）
#
# 幂等：连续 grant 两次只写一次；连续 revoke 第二次返回 :noop。
#
# ## 为什么两个方法都不带 bang
#
# 它们返回 false / :noop 而不是抛。bang 的意思是「炸」，不是「可能失败」——
# 同一份文件里如果 `ac_upsert_visibility_row!`（里面 save! 真会抛）和这两个混着叫 *!，
# 后来人会以为点下去要么成功要么 500。要炸的是 upsert，它带着 bang。

module Scinote
  module AccessControl
    module VisibilityGrant
      WL_ROLE_NAME = 'WL-实验可见(含画布)'
      # 任务级白名单：在 WL 基础上多一个 task_read。
      # 放在 Experiment 上 → experiment_read 让实验可见，task_read 同时充当「含任务」的持久化标记
      #   （job 的 create_or_update_assignment 会把父级行的 user_role 复制到子 MyModule，
      #    所以此后新建的任务会自动带上这个角色 → 放行一次、后续任务自动可见）；
      # 放在 MyModule 上 → task_read 让任务可见。一个角色两处复用。
      WL_TASK_ROLE_NAME = 'WL-实验+任务可见'

      # 出现在 UA 上是「系统给的」，不是「PI 勾的」—— 升级角色时要绕开这两类锚点行
      AC_SYSTEM_ROLES = %w[experiment_owner project_head].freeze

      # 下面几个是给 controller / service 用的公开面。别再用 send 去戳私有方法。
      def ac_wl_role
        @ac_wl_role ||= UserRole.find_by(name: WL_ROLE_NAME, predefined: false)
      end

      def ac_wl_task_role
        @ac_wl_task_role ||= UserRole.find_by(name: WL_TASK_ROLE_NAME, predefined: false)
      end

      # 给成员在本 Experiment 上开「可见壳」。
      #
      # 升级语义：不能简单「已经有一行就跳过」—— 原生 assignable.rb:147-152 与
      # InheritUserAssignmentsJob 会把 Project 上该成员的 Owner/自动行原样复制到 Experiment，
      # 「已经有一行」几乎恒真，会让 PI 勾选后毫无效果（loop_pi_revoke.rb 首次跑就暴露了）。
      #
      # scope: :experiment（默认，实验 + 画布可见）｜ :task（实验 + 任务可见）
      #
      # 关键设计：**「PI 显式放行」与「角色权限」解耦**。
      # PI 勾一格时，成员多半已经因为「项目成员」被父级物化了一行普通角色 ——
      # 若此时直接 return（早期版本），界面上勾选框画完一刷新就变回虚框，PI 会以为系统坏了。
      # 所以：行已存在时**不降级角色**（降级会让 PI 丢掉 experiment_users_manage 之类权限），
      # 只把 assigned 翻成 manually，并把「翻之前它是什么」记进 grant 行 —— revoke 要靠它
      # 决定是「还原」还是「别碰」（见 revoke_member_visibility）。
      def grant_member_visibility(user, scope: :experiment, by: nil)
        return false if user.blank? || !Scinote::AccessControl.enabled?

        role = scope == :task ? ac_wl_task_role : ac_wl_role
        return false if role.nil?

        team_value = respond_to?(:team_id) ? team_id : project&.team_id
        return false if team_value.blank?

        row = user_assignments.find_by(user_id: user.id, team_id: team_value)
        was_manual = row&.manually_assigned? || false

        ac_upsert_visibility_row!(self, user, role, team_value)

        # 任务可见性只存在于 MyModule 层：实验上那一行带不到任务上
        # （permission_granted? 只查对象自身 UA，permission_checkable_model.rb:49-65）。
        # 所以 scope=:task 必须逐个任务落行，否则 PI 勾了「含任务」成员还是看不见。
        if scope == :task
          my_modules.active.find_each do |mod|
            ac_upsert_visibility_row!(mod, user, role, team_value)
          end
        end

        ac_record_grant!(user, scope, was_manual: was_manual, by: by)
        true
      end

      # 撤回 PI 的显式放行。
      #
      # 有 grant 行才动手 —— 这是本方法与「按 user_id 扫手动行」那个旧实现的唯一分界线：
      # 没有 PI 的放行记录时，这个实验上哪怕挂着十行 manually UA，也一行都不碰。
      #
      # 撤 UA 分三种：
      #   · 我们**新建**的 WL 行（was_manual=false 且角色就是 WL）→ destroy
      #   · 我们把**已有的行翻成 manually** 的 → 打回 automatically（翻之前它就是这个值）
      #   · 我们**没动过**的（勾的时候那行本来就是 manually，宿主手工指派给的）→ 不动
      # 第三种是旧实现误伤的地方：它一律打回 automatically，等于替宿主撤销了人工授权。
      def revoke_member_visibility(user, scope: :experiment)
        return :noop if user.blank?

        role = scope == :task ? ac_wl_task_role : ac_wl_role
        return :noop if role.nil?

        return ac_revoke_task_visibility!(user, role) if scope == :task

        grant = ac_grant_for(user, :experiment)
        return :noop if grant.nil?

        team_value = respond_to?(:team_id) ? team_id : project&.team_id
        row = user_assignments.find_by(user_id: user.id, team_id: team_value)

        if row && !grant.was_manual
          if row.user_role_id == role.id
            row.destroy!
          else
            row.update!(assigned: :automatically, assigned_by_id: nil)
          end
        end

        grant.destroy!

        # :still_readable 很重要：PI 勾掉的格子未必真的生效（成员可能同时是项目 Owner
        # 或该实验 creator）。界面据此提示「仍可通过 X 访问」，避免假阴性。
        permission_granted?(user, ExperimentPermissions::READ) ? :still_readable : :revoked
      end

      # 矩阵读数：这一格是不是 PI 显式放过（画实心框的依据）。
      #
      # 以前这里要反推三段（manually + 非系统角色 + 角色含权限），现在只查自己那张表 ——
      # 「PI 有没有勾过」是 addon 的事实，就该查 addon 的表。
      def ac_manually_granted?(user, scope: :experiment)
        return false if user.blank?

        Scinote::AccessControl::ManualGrant.exists?(experiment_id: id, user_id: user.id, scope: scope)
      end

      # 在 target（Experiment 或 MyModule）上 upsert 一行可见性授权。
      # 三种情形：
      #   - 无行          → 建 role 手动行
      #   - 有行且已能读  → 只翻 manually 标记，绝不降级角色（降级会丢 experiment_users_manage 等）
      #   - 有行但读不到  → 升级为 role（系统锚点行除外 —— D3 给 creator 的，不能被 PI 顺手改掉）
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

      private

        def ac_grant_for(user, scope)
          Scinote::AccessControl::ManualGrant.find_by(experiment_id: id, user_id: user.id, scope: scope)
        end

        # scope=:task 的实验格也要画实心 —— WL+task 角色同时带 experiment_read 与 task_read，
        # 放行一次两个 scope 都成立。revoke(:task) 只删 scope=task 那行，实验格保持实心。
        def ac_record_grant!(user, scope, was_manual:, by: nil)
          scopes = scope == :task ? %i[experiment task] : [:experiment]

          scopes.each do |s|
            Scinote::AccessControl::ManualGrant.find_or_create_by!(
              experiment_id: id, user_id: user.id, scope: s
            ) do |grant|
              grant.granted_by_id = by&.id
              grant.was_manual = was_manual
            end
          end
        end

        # 收回「含任务」：撤掉任务可见性，但保留实验可见（PI 只是不想让人碰任务）。
        # 只认 WL+task 这一个角色的行 —— 绝不按 user_id 一刀切，否则会把
        # D3 给 creator 的 task_owner 锚点行一起删掉。
        def ac_revoke_task_visibility!(user, role)
          grant = ac_grant_for(user, :task)
          return :noop if grant.nil?

          my_modules.find_each do |mod|
            rows = mod.user_assignments.where(user_id: user.id, user_role_id: role.id)
            next if rows.none?

            rows.destroy_all
          end

          # 实验上那条是「含任务」的标记行：降级回 WL，去掉 task_read 但保留实验可见。
          row = user_assignments.find_by(user_id: user.id, user_role_id: role.id)
          row.update!(user_role: ac_wl_role) if row && ac_wl_role

          grant.destroy!
          :revoked
        end
    end
  end
end

unless Experiment.instance_variable_get(:@access_control_grant_loaded)
  Experiment.instance_variable_set(:@access_control_grant_loaded, true)

  Experiment.prepend(Scinote::AccessControl::VisibilityGrant)
end
