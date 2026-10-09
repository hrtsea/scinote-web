# frozen_string_literal: true

# ADR-0038-A 修订：收藏功能改为复用宿主原生 favorites（public.favorites 多态表），
# 不再自建 eln_ui_project_stars 表，避免 /projects 与 /eln_project_list 两套收藏数据分裂。
# 删除当初误建的本表。
class DropElnUiProjectStars < ActiveRecord::Migration[7.2]
  def change
    return unless table_exists?(:eln_ui_project_stars)

    remove_index :eln_ui_project_stars, name: 'uniq_eln_ui_project_stars_user_project'
    drop_table :eln_ui_project_stars
  end
end
