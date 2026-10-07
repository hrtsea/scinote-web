# frozen_string_literal: true

# ============================================================================
# 清掉 ResCenter 真机验收在生产库里建的 _seed_ 数据
# ============================================================================
#
# 🔴 生产库纪律：资源中心 4 tab 上线时会在生产库建 _seed_ 库存 / 申请单 /
#   cost_item。验完必须清，否则污染演示 + 生产报表。
#
# ⚠ 字段真相（与原印象不同的修正）：
#   - repository_ledger_records 没有 repository_id 列（通过 repository_stock_value_id 关联）
#   - repository_stock_values 没有 repository_row_id 列（EAV 通过 RepositoryCell 多态挂载）
#   - 库名是新模板路径：'_seed_ 化学品与试剂库存' / '_seed_ 设备库存'（非旧名）
#
# 用法：
#   # 干跑（看会删什么，不删）：
#   docker exec -e DRY=1 <容器> bash -c \
#     "RAILS_ENV=production bin/rails runner /tmp/cleanup_res_center_seed.rb"
#
#   # 真删：
#   docker exec <容器> bash -c \
#     "RAILS_ENV=production bin/rails runner /tmp/cleanup_res_center_seed.rb"
# ============================================================================

DRY = ENV['DRY'].present?

def sweep(scope, label)
  n = scope.count
  if n.zero?
    puts "  #{label}: 0 条"
    return
  end
  puts "  #{label}: #{n} 条"
  scope.find_each { |r| puts "    - ##{r.id} #{r.try(:name) || r.try(:no) || r.class.name}" }
  return if DRY

  deleted = scope.delete_all
  puts "    ✓ deleted #{deleted}"
rescue StandardError => e
  puts "    ✗ 失败：#{e.class}: #{e.message[0..120]}"
end

puts DRY ? '== DRY RUN（不删）==' : '== 真删 =='

# ---- 收集 _seed_ 库存（绑模板：化学品 + 设备）----
puts "\n[1] 找 _seed_ 库（化学品 + 设备）"
seed_repos = RepositoryBase.where(name: ['_seed_ 化学品与试剂库存', '_seed_ 设备库存'])
seed_repo_ids = seed_repos.pluck(:id)
seed_rows = RepositoryRow.where(repository_id: seed_repo_ids)
seed_row_ids = seed_rows.pluck(:id)

# EAV：找 StockValue 通过 cell 多态挂载
seed_sv_ids = if seed_row_ids.any?
                RepositoryStockValue.joins(:repository_cell)
                                    .where(repository_cells: { repository_row_id: seed_row_ids })
                                    .pluck(:id)
              else
                []
              end
seed_column_ids = RepositoryColumn.where(repository_id: seed_repo_ids).pluck(:id)

sweep(seed_repos, 'RepositoryBase  _seed_ 库')
sweep(seed_rows,  'RepositoryRow    _seed_ 行')

puts "\n[2] 清关联 ledger + mmrr + sv + cell + column + unit_item"
sweep(RepositoryLedgerRecord.where(repository_stock_value_id: seed_sv_ids),
      'RepositoryLedgerRecord  关联 _seed_ sv')
sweep(MyModuleRepositoryRow.where(repository_row_id: seed_row_ids),
      'MyModuleRepositoryRow   关联 _seed_ 行')
sweep(RepositoryStockValue.where(id: seed_sv_ids),
      'RepositoryStockValue    关联 _seed_ 行（EAV 反查）')
sweep(RepositoryCell.where(repository_row_id: seed_row_ids),
      'RepositoryCell         关联 _seed_ 行')
sweep(RepositoryStockUnitItem.where(repository_column_id: seed_column_ids),
      'RepositoryStockUnitItem 关联 _seed_ col')
sweep(RepositoryColumn.where(repository_id: seed_repo_ids),
      'RepositoryColumn       关联 _seed_ 库')

puts "\n[3] 清 eln_ui_* 申请 + 花费"
sweep(Scinote::ElnUi::ResourceApplication
        .where(no: ['SQ-2026-7777',
                    'SQ-2026-0090', 'SQ-2026-0091',
                    'SQ-2026-0092', 'SQ-2026-0093']),
      'eln_ui_resource_applications  SQ-2026-7777 / 0090~93')
sweep(Scinote::ElnUi::ProjectCostItem.where('source LIKE ?', '_seed_%'),
      'eln_ui_project_cost_items    source LIKE _seed_%')

puts "\n== 完毕 #{'(DRY)' if DRY} =="
exit 0
