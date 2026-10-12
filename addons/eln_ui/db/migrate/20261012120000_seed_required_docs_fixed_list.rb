# frozen_string_literal: true

# 一次性补种：必传文档固定清单化（ADR-0049 · REQ-PM-DOCS）。
#
# 背景：必传文档 5 类是固定清单，但 eln_ui_project_documents 是登记台账，行不会
# 凭空出现。本迁移把「已纳管」（有二开项目档案）的历史项目补齐到规范清单：
#   1. required 行名洗 `_seed_` 前缀（早期手工种数据的残留，数据与上传态保留）；
#   2. canonical 5 类补缺 + position 归一 1..5。
#
# 🔴 自含快照：下面这份列表是**迁移时点的冻结快照**，不追随后端常量漂移。运行时
#   对应物是 Scinote::ElnUi::RequiredDocSeeder::REQUIRED_DOC_NAMES（show 懒补种），
#   两者故意不共享常量 —— 迁移要能在任何将来的代码状态下重放。
#
# 🔴 洗前缀必须 Ruby 侧 start_with?：SQL `LIKE '_seed_%'` 里 `_` 是单字符通配符，
#   '_seed_%' 会误匹配 "Xseed…" 这类名字。
#
# 🔴 顺序：先洗白后补缺。项目 36 的 "_seed_立项申请材料" 洗白后正好命中 canonical
#   名，find_or_initialize 不会重复建行。
#
# 不可逆声明：补种新增的行无法与用户自建行区分，down 不猜，直接 raise。
class SeedRequiredDocsFixedList < ActiveRecord::Migration[7.2]
  # 匿名模型：迁移是历史快照，不引用 app/models 下的 Scinote::ElnUi::ProjectDocument
  #   —— 那个类有 scope / has_one_attached，将来任何改动都会让本迁移行为漂移。
  #   本迁移只需要最裸的 CRUD：project_id / name / category / position。
  class MigrationProjectDocument < ActiveRecord::Base
    self.table_name = 'eln_ui_project_documents'
  end

  class MigrationProjectProfile < ActiveRecord::Base
    self.table_name = 'eln_ui_project_profiles'
  end

  REQUIRED_DOC_NAMES = %w[立项申请材料 项目任务书 年度计划 年度报告 结题报告].freeze

  def up
    MigrationProjectProfile.find_each do |profile|
      project_id = profile.project_id
      docs = MigrationProjectDocument.where(project_id: project_id, category: 'required')

      docs.find_each do |doc|
        next unless doc.name.start_with?('_seed_')

        doc.update!(name: doc.name.delete_prefix('_seed_'))
      end

      REQUIRED_DOC_NAMES.each_with_index do |name, idx|
        doc = docs.find_or_initialize_by(name: name)
        doc.position = idx + 1
        doc.save!
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
