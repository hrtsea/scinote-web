# frozen_string_literal: true

# 任务关闭审核单（eln_ui_task_close_requests · REQ-TASK-CLOSE / SCN-TASK-CLOSE-1..4）
#
# 为什么必须有这张表（而不是直接改 my_modules.state）：
#   规格里任务关闭是**两段**——执行人先「提交完成申请」，任务进入「待审核」，
#   再由项目负责人审核通过才「已关闭」；驳回还要留理由并退回前序状态。
#   原生 my_modules 只有一个 state 列，装不下「待审核」这一档，也没有 reviewer/reason 列，
#   而本 addon 的铁律是**不动原生表**。所以整条审核轨迹落在这里：
#   待审核 = 有 pending 行；已关闭 = 有 approved 行；驳回留痕 = rejected 行 + reason。
#
# 一条任务可以有多次申请（驳回后再次提交），取当前态看最新一行即可。
class CreateElnUiTaskCloseRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_task_close_requests do |t|
      t.references :my_module,    null: false, foreign_key: { to_table: :my_modules }
      t.string   :status, null: false, default: 'pending'  # pending 待审核 / approved 已关闭 / rejected 已驳回
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }
      t.datetime :submitted_at, null: false
      t.references :reviewer,     foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text     :reason                                   # 驳回理由（SCN-TASK-CLOSE-4 驳回必填）
      t.timestamps
    end

    # 「这个任务当前处于哪一档审核态」是唯一查询路径（列表/详情/闸门三处共用）
    add_index :eln_ui_task_close_requests, %i[my_module_id status]
    add_index :eln_ui_task_close_requests, %i[my_module_id submitted_at]
  end
end
