# frozen_string_literal: true

# 服务执行归属任务（eln_ui_resource_applications + my_module_id · REQ-RES-TEST-STRIKE）
#
# 为什么加这一列：
#   spec V1.21 L998 明写「结果文件必须以 ResultAsset 形式上传至**该次执行所在任务的
#   Results**」—— 也就是说一次测试表征执行天生是**任务级**的，不是项目级的。
#   而 REQ-RES-TEST-STRIKE 的闸门又要求「把任务标记为完成时，校验该任务是否存在
#   已到期仍未回填的执行单」。没有这列，后果（Consequence）只能拿到 task，
#   却查不到该任务下挂了哪些服务执行单 —— 闸门就成了摆设。
#
# ⚠ 只动 addon 自有表（eln_ui_*）：不碰原生 my_modules，也不动原生任务状态流。
class AddMyModuleIdToElnUiResourceApplications < ActiveRecord::Migration[7.2]
  def change
    add_reference :eln_ui_resource_applications, :my_module,
                  foreign_key: { to_table: :my_modules }
    add_index :eln_ui_resource_applications, %i[my_module_id status]
  end
end
