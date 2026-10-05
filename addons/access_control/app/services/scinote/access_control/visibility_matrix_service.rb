# frozen_string_literal: true

# D9.4 —— 可见性矩阵读数（纯 Ruby，无 Rails 视图依赖，方便 loop 脚本直测）
#
# 输入一个 Project，输出「项目成员 × 项目下实验」的二维读数：
#   visible → 该成员现在能不能读这个实验（含项目级继承、owner 自动行、D3 creator 锚点）
#   manual  → 该格子是不是 PI 在界面上显式放行的（WL 角色 + manually）
#
# 两个读数必须分开：界面勾选框画 manual，灰显/箭头标 visible。
# 只看 manual 会让 PI 以为勾了就生效（其实成员可能早已通过项目 Owner 可读）；
# 只看 visible 又会显示一堆 PI 从没开过的格子，矩阵失去意义。

module Scinote
  module AccessControl
    class VisibilityMatrixService
      def self.call(project)
        new(project).call
      end

      # D5 —— 「一键补回继承」
      #
      # 背景（实测）：策略从 isolated 切回 inherit 时，**存量实验不会自动补回** ——
      # 开关只影响之后新建的实验。PI 切完会发现存量成员还是看不见，很困惑。
      #
      # 好消息：**不需要快照表**。本 addon 的隔离是「在 job 里拦截复制」而非「删行」，
      # 所以补回只需对存量对象重跑一次 InheritUserAssignmentsJob —— 该补谁、补什么角色，
      # 都能从 Project 现有的 UA 直接推导出来（job 复制的就是父级 UA 的 user_role）。
      # 这直接否掉了词汇表 §14「需保存快照才能自动化回滚」的设想。
      #
      # 安全边界：job 第 96 行 `return if manually_assigned?`，所以在 isolated 期间
      # PI 显式放行的格子（manually）不会被覆盖，补回只填自动行。
      def self.backfill!(project, assigner:)
        new(project).backfill!(assigner)
      end

      def initialize(project)
        @project = project
      end

      def backfill!(assigner)
        # 注意：enum 声明时**没加 prefix**，所以判据是 `inherit?` 而不是
        # `experiment_visibility_inherit?`（后者不存在，实测）。
        return { skipped: 'not_inherit' } unless @project.inherit?
        return { skipped: 'no_assigner' } if assigner.blank?

        experiments_count = 0
        tasks_count = 0

        @project.experiments.active.find_each do |exp|
          UserAssignments::InheritUserAssignmentsJob.perform_now(exp, assigner_id: assigner.id)
          experiments_count += 1

          # job 只处理传入的 object，不会自己下钻 —— 任务层必须逐个跑，
          # 否则补回来的实验仍是个「空壳」（实验可见、任务不可见，词汇表 §16）。
          exp.my_modules.active.find_each do |task|
            UserAssignments::InheritUserAssignmentsJob.perform_now(task, assigner_id: assigner.id)
            tasks_count += 1
          end
        end

        { backfilled: true, experiments: experiments_count, tasks: tasks_count }
      end

      def call
        members = @project.users.order(:full_name)
        experiments = @project.experiments.active.order(name: :asc)

        {
          project: { id: @project.id, name: @project.name },
          members: members.map { |m| member_json(m) },
          experiments: experiments.map { |e| experiment_json(e) },
          cells: cells(members.to_a, experiments.to_a)
        }
      end

      private

      def member_json(member)
        {
          id: member.id,
          name: member.name,
          full_name: member.full_name,
          avatar_url: (member.avatar_path(:icon_small) if member.respond_to?(:avatar_path))
        }
      end

      def experiment_json(experiment)
        {
          id: experiment.id,
          name: experiment.name,
          task_count: experiment.my_modules.active.count
        }
      end

      def cells(members, experiments)
        cells = {}
        members.each do |member|
          experiments.each do |exp|
            key = cell_key(member.id, exp.id)
            cells[key] = cell_json(exp, member)
          end
        end
        cells
      end

      # 一格有三个读数：
      #   visible            → 成员能不能读这个实验（含项目继承、owner 自动行、D3 creator 锚点）
      #   manual             → 这一格是不是 PI 显式放过实验壳
      #   task_manual        → 这一格是不是 PI 显式放过「连任务一起看」
      #   task_visible_count → 该实验下成员实际能读几个任务（部分放行时会介于 0 和总数之间）
      #
      # 前两个必须分开：只看 manual 会让 PI 以为勾了才生效（其实成员可能早就能读）；
      # 只看 visible 又会显示一堆 PI 从没开过的格子。task_* 同理 —— 实验可见 ≠ 任务可见，
      # 这是 permission_granted? 只查对象自身 UA 导致的硬约束（词汇表 §16）。
      def cell_json(exp, member)
        {
          visible: exp.permission_granted?(member, ExperimentPermissions::READ),
          manual: exp.respond_to?(:ac_manually_granted?, true) ? exp.send(:ac_manually_granted?, member) : false,
          task_manual: exp.respond_to?(:ac_manually_granted?, true) ? exp.send(:ac_manually_granted?, member, scope: :task) : false,
          task_visible_count: exp.my_modules.active.count { |m| m.permission_granted?(member, MyModulePermissions::READ) }
        }
      end

      def cell_key(user_id, experiment_id)
        "#{user_id}-#{experiment_id}"
      end
    end
  end
end
