# frozen_string_literal: true

# OPEN-11 —— Project 上的「新建实验默认可见性」读写面（真源 = addon 自有表）
#
# 为什么属性名**不叫** experiment_visibility_strategy：
#   那正是原生列的名字。列还留在 projects 表上（铁律不允许 addon 去 drop 原生结构），
#   若这里再定义一个同名方法，AR attribute 与我们的方法就会并存 ——
#   `project.experiment_visibility_strategy` 走我们的方法，而
#   `Project.where(experiment_visibility_strategy: 1)` / `pluck` / 任何后台 SQL 走列，
#   同一个名字两个真源，必然有人读到旧值（而且是静默的）。
#   所以换个名字，让「那根列已经不作数」这件事在代码里看得见。
#
# ac_ 前缀是本 addon 注入宿主模型的方法的统一前缀（同 ac_manually_granted?）。

module Scinote
  module AccessControl
    module ProjectStrategyAccess
      def self.prepended(base)
        # 支持「先赋值、后保存」的写法：测试工厂与 `Project.new(strategy: ...)`
        # 都是这个形状，而那时还没有 id 可写表。先留在实例上，create 之后落表。
        base.after_create :ac_flush_pending_strategy!
      end

      # 读：memo 一次。job 里每个新建实验都要问一次（assign_to_experiment），
      # 不 memo 就是「实验数」次查询，而它在一个 job 的生命周期内不会变。
      def ac_visibility_strategy
        @ac_visibility_strategy ||= Scinote::AccessControl::ProjectStrategy.strategy_for(id)
      end

      # 写：非法值由 ProjectStrategy.normalize! 抛 ArgumentError（controller 翻成 422）。
      def ac_visibility_strategy=(value)
        name = Scinote::AccessControl::ProjectStrategy.normalize!(value)
        @ac_visibility_strategy = name

        Scinote::AccessControl::ProjectStrategy.set!(id, name) if persisted?
        name
      end

      def ac_isolated?
        ac_visibility_strategy == 'isolated'
      end

      def ac_inherit?
        ac_visibility_strategy == 'inherit'
      end

      private

      def ac_flush_pending_strategy!
        return if @ac_visibility_strategy.nil?

        Scinote::AccessControl::ProjectStrategy.set!(id, @ac_visibility_strategy)
      end
    end
  end
end

# 一行守卫就够：开发模式 to_prepare 走 load 会重跑本文件，不 return 就重复挂 after_create。
unless Project.instance_variable_get(:@access_control_project_strategy_loaded)
  Project.instance_variable_set(:@access_control_project_strategy_loaded, true)

  Project.prepend(Scinote::AccessControl::ProjectStrategyAccess)
end
