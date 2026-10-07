# frozen_string_literal: true

# D5 —— 「一键补回继承」（Project#backfill_inherited_assignments!）
#
# 为什么长在 Project 上：这是对存量对象重跑一次继承 job 的**纯领域动作**，
# 跟「读出一个矩阵」没有任何关系。它原来住在 VisibilityMatrixService.backfill! 里，
# 同词两义的结果是那个 service 既不敢删也不敢改名。挪回来之后调用点就是
# `project.backfill_inherited_assignments!(by: current_user)`。
#
# 背景（实测）：策略从 isolated 切回 inherit 时，**存量实验不会自动补回** ——
#   开关只影响之后新建的实验。PI 切完会发现存量成员还是看不见，很困惑。
#
# 为什么不需要快照表：本 addon 的隔离是「在 job 里拦截复制」而非「删行」，
#   所以补回只需对存量对象重跑一次 InheritUserAssignmentsJob —— 该补谁、补什么角色，
#   都能从 Project 现有的 UA 直接推导出来（job 复制的就是父级 UA 的 user_role）。
#   这直接否掉了词汇表 §14「需保存快照才能自动化回滚」的设想。
#
# 安全边界：job 第 96 行 `return if manually_assigned?`，所以 PI 显式放行的格子
#   （manually）不会被覆盖，补回只填自动行。

module Scinote
  module AccessControl
    module ProjectBackfill
      # 返回值契约：成功 { backfilled: true, experiments:, tasks: }｜
      #            跳过 { skipped: :not_inherit | :no_assigner }
      # 用 symbol 不用字符串字面量 —— 这是给调用方分支用的枚举，不是文案。
      def backfill_inherited_assignments!(by:)
        # ac_inherit? 的真源是 addon 自有表（OPEN-11）。
        return { skipped: :not_inherit } unless ac_inherit?
        return { skipped: :no_assigner } if by.blank?

        experiments_count = 0
        tasks_count = 0

        experiments.active.find_each do |exp|
          UserAssignments::InheritUserAssignmentsJob.perform_now(exp, assigner_id: by.id)
          experiments_count += 1

          # job 只处理传入的 object，不会自己下钻 —— 任务层必须逐个跑，
          # 否则补回来的实验仍是个「空壳」（实验可见、任务不可见，词汇表 §16）。
          exp.my_modules.active.find_each do |task|
            UserAssignments::InheritUserAssignmentsJob.perform_now(task, assigner_id: by.id)
            tasks_count += 1
          end
        end

        { backfilled: true, experiments: experiments_count, tasks: tasks_count }
      end
    end
  end
end

unless Project.instance_variable_get(:@access_control_backfill_loaded)
  Project.instance_variable_set(:@access_control_backfill_loaded, true)

  Project.prepend(Scinote::AccessControl::ProjectBackfill)
end
