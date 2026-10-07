# frozen_string_literal: true

# D9.4 —— 可见性矩阵的**读数**（纯 Ruby，无 Rails 视图依赖，方便 loop 脚本直测）
#
# 输入一个 Project，输出「项目成员 × 项目下实验」的二维读数：
#   visible → 该成员现在能不能读这个实验（含项目级继承、owner 自动行、D3 creator 锚点）
#   manual  → 该格子是不是 PI 在界面上显式放行的
#
# 两个读数必须分开：界面勾选框画 manual，灰显/箭头标 visible。
# 只看 manual 会让 PI 以为勾了就生效（其实成员可能早已通过项目 Owner 可读）；
# 只看 visible 又会显示一堆 PI 从没开过的格子，矩阵失去意义。
#
# 写侧在 VisibilityGrant（prepend 到 Experiment 的那一个），读侧在这里 ——
# 「矩阵」这个词只属于本文件：这一份输出才真的是一张矩阵。

module Scinote
  module AccessControl
    class VisibilityMatrixService
      def initialize(project)
        @project = project
      end

      def call
        members = @project.users.order(:full_name).to_a
        experiments = @project.experiments.active.order(name: :asc).to_a

        # 任务列表每个实验只拉一次。原来 cell_json 里写的是 `exp.my_modules.active`，
        # 每画一格就重查一遍 → M 个成员 × E 个实验 = M×E 次完全一样的查询。
        tasks_by_exp = experiments.each_with_object({}) { |exp, acc| acc[exp.id] = exp.my_modules.active.to_a }

        # 「PI 勾过哪些格」两次查询拿全（一次一个 scope）。
        # 原来是每格现查 UA 再逐行读 user_role 反推 —— M×E×(1+N) 次查询，
        # 全在 PI 打开页面的那一刻付。现在跟 M、E 无关。
        experiment_ids = experiments.map(&:id)
        member_ids = members.map(&:id)
        grants = {
          experiment: ManualGrant.keys_for(experiment_ids, member_ids, :experiment),
          task: ManualGrant.keys_for(experiment_ids, member_ids, :task)
        }

        {
          project: { id: @project.id, name: @project.name },
          members: members.map { |m| member_json(m) },
          experiments: experiments.map { |e| experiment_json(e, tasks_by_exp[e.id]) },
          cells: cells(members, experiments, tasks_by_exp, grants)
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

        def experiment_json(experiment, tasks)
          {
            id: experiment.id,
            name: experiment.name,
            task_count: tasks.size
          }
        end

        def cells(members, experiments, tasks_by_exp, grants)
          members.each_with_object({}) do |member, acc|
            experiments.each do |exp|
              acc[cell_key(member.id, exp.id)] = cell_json(exp, member, tasks_by_exp[exp.id], grants)
            end
          end
        end

        # 一格有四个读数：
        #   visible            → 成员能不能读这个实验（含项目继承、owner 自动行、D3 creator 锚点）
        #   manual             → 这一格是不是 PI 显式放过实验壳
        #   task_manual        → 这一格是不是 PI 显式放过「连任务一起看」
        #   task_visible_count → 该实验下成员实际能读几个任务（部分放行时会介于 0 和总数之间）
        #
        # 前两个必须分开：只看 manual 会让 PI 以为勾了才生效（其实成员可能早就能读）；
        # 只看 visible 又会显示一堆 PI 从没开过的格子。task_* 同理 —— 实验可见 ≠ 任务可见，
        # 这是 permission_granted? 只查对象自身 UA 导致的硬约束（词汇表 §16）。
        #
        # ⚠ visible / task_visible_count 仍然逐格调原生 permission_granted?。
        #   它不是「查一下 UA 行」这么简单 —— 内部还有 group 指派 / team 指派两个分支，
        #   在 Ruby 侧自己复刻一遍 UA 查询会**漏掉组可见性和团队可见性**，
        #   省下的这点查询换一个假阴性不划算。真要降本，正确方向是「写时算」
        #   （job 跑完把可见用户物化），不是在读的时候猜。
        def cell_json(exp, member, tasks, grants)
          {
            visible: exp.permission_granted?(member, ExperimentPermissions::READ),
            manual: grants[:experiment].include?([exp.id, member.id]),
            task_manual: grants[:task].include?([exp.id, member.id]),
            task_visible_count: tasks.count { |m| m.permission_granted?(member, MyModulePermissions::READ) }
          }
        end

        def cell_key(user_id, experiment_id)
          "#{user_id}-#{experiment_id}"
        end
    end
  end
end
