# frozen_string_literal: true

# PI 显式放行的一格（access_control_manual_grants）
#
# 表里那一行就是「PI 在可见性矩阵里勾过 (实验, 成员, scope)」这个事实的全部证据 ——
# UA 行上的 `assigned: :manually` 不认来源（宿主后台手工指派也写它），不能拿来当判据。
#
# ⚠ 与 eln_ui_* 同源铁律：表名显式 self.table_name；类体裹 module Scinote::AccessControl；
#   不建指向原生表的关联（本表只被按 experiment_id / user_id 查，不需要 belongs_to）。
#
# ⚠ enum 名 `scope` 不加 prefix：想用的是 `ManualGrant.where(scope: :task)` 这种短写法。
#   （`scope` 是 AR 的**类**方法名，enum 只占实例方法与 `ManualGrant.scopes`，不冲突。）
module Scinote
  module AccessControl
    class ManualGrant < ActiveRecord::Base
      self.table_name = 'access_control_manual_grants'

      enum :scope, { experiment: 0, task: 1 }

      # 「这一批 (实验, 成员) 里哪些格被放行过」—— 矩阵读数走它，
      # 一次查询顶掉原来的 M×E 次逐格推断。
      def self.keys_for(experiment_ids, user_ids, scope)
        return [].to_set if experiment_ids.blank? || user_ids.blank?

        where(experiment_id: experiment_ids, user_id: user_ids, scope: scope)
          .pluck(:experiment_id, :user_id)
          .to_set
      end
    end
  end
end
