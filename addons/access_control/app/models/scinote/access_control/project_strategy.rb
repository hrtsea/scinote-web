# frozen_string_literal: true

# OPEN-11 —— 「项目的新建实验默认可见性」的真源（addon 自有表）
#
# 取代原先落在原生 `projects.experiment_visibility_strategy` 上的一根列。
# 表语义见 migration 注释：**只记录偏离默认（inherit）的项目**，没有行就是 inherit。
#
# 为什么读侧要给 `strategy_for`：调用点要的是 `'inherit' / 'isolated'` 这个名字，
# 而不是裸整数。
module Scinote
  module AccessControl
    class ProjectStrategy < ActiveRecord::Base
      self.table_name = 'access_control_project_strategies'

      # 与原生列当年的 enum 取值保持一致（0=inherit / 1=isolated），
      # 回填时按这个对照搬，别改数字。
      STRATEGIES = { 'inherit' => 0, 'isolated' => 1 }.freeze
      DEFAULT    = 'inherit'.freeze

      class << self
        # 读：没有行、或 project_id 为空（未保存的 Project）→ 原生默认
        def strategy_for(project_id)
          return DEFAULT if project_id.blank?

          STRATEGIES.key(where(project_id: project_id).pick(:strategy).to_i) || DEFAULT
        end

        # 写：inherit 是默认值 → **删行**，让「表里的行 = 偏离默认的项目」这个不变式成立。
        # 非法值直接抛 ArgumentError（controller 已把它翻成 422）——
        # 静默猜一个值正是上一轮修掉的那个 bug。
        def set!(project_id, value)
          name = normalize!(value)

          if name == DEFAULT
            where(project_id: project_id).delete_all
          else
            find_or_initialize_by(project_id: project_id).update!(strategy: STRATEGIES[name])
          end

          name
        end

        # 校验 + 归一。返回值是名字字符串（'inherit' / 'isolated'）。
        def normalize!(value)
          name = value.to_s
          return name if STRATEGIES.key?(name)

          raise ArgumentError,
                "unknown experiment visibility strategy: #{value.inspect} " \
                "(expected one of #{STRATEGIES.keys.join(' / ')})"
        end
      end
    end
  end
end
