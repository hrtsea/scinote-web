# frozen_string_literal: true

# 任务级二开档案（eln_ui_task_profiles）—— 原生 my_modules 没有 purpose / plan 列，
# 这两个字段的承载面只能由 addon 自建。
#
# ⚠ class_name 必须带 `::` 前缀：本 engine `isolate_namespace Scinote::ElnUi`，
#   写 `belongs_to :my_module` 会被解析成不存在的 Scinote::ElnUi::MyModule，
#   直到运行时才炸（Zeitwerk 不报、关联抛 NameError）。实验档案那条是同一个坑。
#
# ⚠ 2026-10-04 炸过一次：这里原来写成**顶层** `class TaskProfile`（不裹 module），
#   Zeitwerk 按路径期望的是 `Scinote::ElnUi::TaskProfile`，eager_load 时期望的常量
#   和文件里定义的常量对不上 → `Zeitwerk::NameError` → **整站起不来**（不是某个页面 500，
#   是容器 boot 直接 exit 1）。同目录 design_variable.rb / experiment_profile.rb 都是
#   裹在 `module Scinote; module ElnUi` 里的，就它们仨底下两个文件一开始漏了 module。
#   以后往这个目录加模型，先照 design_variable.rb 抄外壳。
module Scinote
  module ElnUi
    class TaskProfile < ActiveRecord::Base
      self.table_name = 'eln_ui_task_profiles'

      belongs_to :my_module, class_name: '::MyModule', inverse_of: false
      belongs_to :owner_user, class_name: '::User', optional: true

      def self.upsert_for!(my_module, attrs)
        find_or_initialize_by(my_module_id: my_module.id)
          .tap { |record| record.update!(attrs.merge(my_module: my_module)) }
      end
    end
  end
end
