# frozen_string_literal: true

# eln_ui 项目列表「收藏 / 星标」（per-user，见迁移注释）
#
# ⚠ 与 eln_ui 其它 model 同源铁律：
#   · 基类 ActiveRecord::Base（engine 不自带 ApplicationRecord，宿主也不应被污染）；
#   · 显式 self.table_name（Rails 推不出 eln_ui_project_stars 的复数歧义）。
# 跨命名空间引用宿主 Project / User，用 class_name 全限定。
module Scinote
  module ElnUi
    class ProjectStar < ActiveRecord::Base
      self.table_name = 'eln_ui_project_stars'

      belongs_to :user, class_name: 'User'
      belongs_to :project, class_name: 'Project'

      # 同一用户对同一项目只能收藏一次（与 DB 唯一索引 uniql_eln_ui_project_stars_user_project 双保险）。
      validates :user_id, uniqueness: { scope: :project_id }
    end
  end
end
