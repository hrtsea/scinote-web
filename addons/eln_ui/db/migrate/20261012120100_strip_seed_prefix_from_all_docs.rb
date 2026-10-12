# frozen_string_literal: true

# 补丁：完成 _seed_ 前缀全量规范化（ADR-0049 · G4/D5）。
#
# 20261012120000 SeedRequiredDocsFixedList 按 spec §4.3 只洗了 category='required'
# 的行；实测发现项目 36 还有 2 行 category='other' 同样带 _seed_ 前缀
# （"_seed_填料批次送样单.xlsx" / "_seed_压阻测试原始数据.csv"）—— 早期同一批
# 手工种数据的残留。ADR-0049 D5/G4 的决策原文是「历史 _seed_ 手工种数据规范化」，
# 不带 category 限定：_seed_ 是测试数据标记，任何面板都不该露出前缀。
#
# 本补丁对**所有 category** 洗前缀（幂等：再跑零改动），只改 name，
# 不动 uploaded / uploaded_on / version / position 等数据。
#
# 🔴 同 20261012120000：必须 Ruby 侧 start_with?，SQL LIKE '_seed_%' 的 '_'
#   是单字符通配符会误匹配。
class StripSeedPrefixFromAllDocs < ActiveRecord::Migration[7.2]
  class MigrationProjectDocument < ActiveRecord::Base
    self.table_name = 'eln_ui_project_documents'
  end

  def up
    MigrationProjectDocument.find_each do |doc|
      next unless doc.name.start_with?('_seed_')

      doc.update!(name: doc.name.delete_prefix('_seed_'))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
