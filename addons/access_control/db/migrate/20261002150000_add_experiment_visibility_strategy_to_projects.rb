# frozen_string_literal: true

# D2 —— 项目级「实验默认可见性策略」
#
#   inherit  (0, 默认) 原生行为：新建实验时把项目成员/组/团队的指派复制进实验 → 成员自动可见
#   isolated (1)       隔离：新建实验**不**复制普通成员的行，只保留管理者与创建者，
#                      其余成员由 PI 在可见性矩阵里逐格放行
#
# 为什么是 Project 上的列而不是全局配置：
#   同一个实例里「课题组内部项目希望全组可见」与「有外部合作的项目希望默认隔离」会并存，
#   全局开关必然有一边妥协。放在 Project 上，默认 inherit 保证不动任何存量行为。
#
# 为什么是 integer 而不是 boolean：
#   以后还要加第三种（比如「只隔离新建、不改存量」或按角色白名单），boolean 撑不住。

class AddExperimentVisibilityStrategyToProjects < ActiveRecord::Migration[7.2]
  def change
    add_column :projects, :experiment_visibility_strategy, :integer, default: 0, null: false
  end
end
