# frozen_string_literal: true

# 三处 prepend 装饰器（Experiment creator / MyModule creator / Project head）共用的一小块。
#
# 角色锚点行的读写 —— 查角色、在 (user, team) 上找/建一行、必要时翻 manually。
#
# 角色查找和 team_id 兜底也放这里：Experiment / MyModule 上**没有** team_id
# （实测 Experiment.instance_methods.include?(:team_id) == false），
# Project 上才有，所以三处都得写 `respond_to?(:team_id) ? team_id : project&.team_id` 这个形状。
#
# 只抽这一块。upsert 之后「要不要动 assigned」每处判据都不同
# （Experiment 看 manually_assigned?、MyModule 看 task_read、Project head 看 project_manage），
# 硬塞进一个参数会变 too clever —— 宁可各处留那个 if。

module Scinote
  module AccessControl
    module AnchorAssignment
      private

        def ac_role(name)
          UserRole.find_by(name: name, predefined: false)
        end

        def ac_team_id_of(fallback = nil)
          respond_to?(:team_id) ? team_id : fallback
        end

        # (user, team) 上的锚点行。
        #
        # find_or_initialize 而不是「先 find 再 create」：并发下靠原生唯一索引
        # (assignable_type, assignable_id, user_id, team_id) 兜（索引里没有角色，
        # 自己先查后建会撞 "User has already been taken"）。
        #
        # assigned 的语义在两处不一样，分离对待：
        #   - 新建：锚点就是「人工指定的身份/授权」，必须落 manually（Project head 那行
        #     全靠 assigned: :manually 才能被 revoke 认出来，见 job:96）。
        #   - 已有行：默认**不动** assigned / assigned_by_id —— Project head 的升级分支
        #     只升角色，翻成 manually 会让后续的 head 变更认错行；要翻就显式传参。
        def ac_anchor_row!(role, user_id, team, assigned: nil, assigned_by_id: nil)
          row = user_assignments.find_or_initialize_by(user_id: user_id, team_id: team)
          row.user_role = role

          if row.new_record?
            row.assigned = assigned || :manually
            row.assigned_by_id = assigned_by_id || user_id
          else
            row.assigned = assigned if assigned
            row.assigned_by_id = assigned_by_id if assigned_by_id
          end

          row.save!
          row
        end
    end
  end
end
