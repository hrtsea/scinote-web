# frozen_string_literal: true

# ============================================================================
# Seed：资源库存（用原生 RepositoryTemplate 模板 + RepositoryCell EAV 多态）
# ============================================================================
#
# 用途：让资源中心 4 tab 全部走真数据（库存真接原生体系）：
#   - 「资源台账」         → 有库存 + 行 + Stock/单位
#   - 「消耗/执行明细」    → 有出库 LedgerRecord（reference=mmrr）
#   - 「项目花费」         → 有出库 LedgerRecord + unit_price 快照，可按 project_id 聚合
#   - 「资源申请」         → 不在这里 seed（走 seed_resource_applications.rb）
#
# 关键决策：库存绑原生 RepositoryTemplate
#   - 化学品与试剂 → 模板 id 指向 RepositoryTemplate.chemicals_and_reagents
#   - 设备         → 模板 id 指向 RepositoryTemplate.equipment
#   - 即使本次只建 Stock 列（其他模板列不展开），库存形态已对齐原生 Invertories 索引页
#
# EAV 链路：
#   Repository (template_id=chemicals_template)
#     └── RepositoryColumn (data_type='RepositoryStockValue')
#                 └── RepositoryStockUnitItem (data='kg'/'次')
#     └── RepositoryRow
#                 └── RepositoryCell (多态 value_type='RepositoryStockValue', value_id=sv.id)
#                                         ↓ 反查
#                              RepositoryStockValue (amount=120, repository_stock_unit_item=unit_item)
#   StockValue.after_create 自动写一笔入库 LedgerRecord（reference=column.repository）
#
# 用法（容器内）：
#   bin/rails runner /tmp/seed_inventory.rb            # 灌
#   bin/rails runner /tmp/seed_inventory.rb --rollback # 清（按 _seed_ 前缀）
# ============================================================================

ROLLBACK = ARGV.include?('--rollback')

# ---- 取真实上下文 ----
# ⚠ rails runner 没有 controller 上下文，current_team 不存在 → 直接 Team.first
team = Team.first
abort '✗ 没有 team（生产库须先有至少一个 team）' if team.nil?

admin = ::User.find_by(email: 'hpxing@localhost') || ::User.order(:id).first
abort '✗ 没有用户' if admin.nil?

proj_pp = ::Project.where(team_id: team.id, archived: false)
                   .where('name LIKE ?', '%PP%').first
proj_pp ||= ::Project.where(team_id: team.id, archived: false).first
abort '✗ 当前 team 下没有任何 active project' if proj_pp.nil?

exp = proj_pp.experiments.where(archived: false).first ||
      proj_pp.experiments.first
my_module = exp&.my_modules&.where(archived: false)&.first ||
            (exp ? MyModule.where(experiment_id: exp.id).first : nil)
abort '✗ 没有可用 MyModule（请先建一个任务）' if my_module.nil?

# ---- 取预置模板（团队创建时 Team.after_create 已自动下发 4 套）----
# ⚠ 关键：原生没有 COLUMN_DEFINITIONS 常量，列定义是从 `RepositoryTemplate.chemicals_and_reagents`
#   方法返回的内存对象上读 column_definitions（jsonb 列）
chem_tmpl = team.repository_templates.find_by(
  name: RepositoryTemplate.chemicals_and_reagents.name
) || begin
  t = RepositoryTemplate.chemicals_and_reagents
  t.team = team
  t.predefined = true
  t.save!
  t
end
abort '✗ 化学品与试剂模板缺失' if chem_tmpl.id.nil?

equip_tmpl = team.repository_templates.find_by(
  name: RepositoryTemplate.equipment.name
) || begin
  t = RepositoryTemplate.equipment
  t.team = team
  t.predefined = true
  t.save!
  t
end
abort '✗ 设备模板缺失' if equip_tmpl.id.nil?

puts "==> team = ##{team.id} #{team.name.inspect}"
puts "==> templates: 化学品 ##{chem_tmpl.id}, 设备 ##{equip_tmpl.id}"
puts "==> project = ##{proj_pp.id} #{proj_pp.name.inspect}"
puts "==> experiment = ##{exp.id} #{exp.name.inspect}"
puts "==> my_module = ##{my_module.id} #{my_module.name.inspect}"

# ---- 回滚 ----
def rollback_seed(team, proj_pp)
  n = 0
  repos = RepositoryBase.where(team_id: team.id, name: [
    '_seed_ 化学品与试剂库存',
    '_seed_ 设备库存'
  ])
  repo_ids = repos.pluck(:id)
  row_ids = RepositoryRow.where(repository_id: repo_ids).pluck(:id)
  n += RepositoryCell.where(repository_row_id: row_ids).delete_all
  col_ids = RepositoryColumn.where(repository_id: repo_ids).pluck(:id)
  sv_ids = RepositoryStockValue.joins(:repository_cell)
                               .where(repository_cells: { repository_column_id: col_ids })
                               .pluck(:id)
  n += RepositoryStockValue.where(id: sv_ids).delete_all
  n += RepositoryStockUnitItem.where(repository_column_id: col_ids).delete_all
  n += RepositoryColumn.where(id: col_ids).delete_all
  # LedgerRecord（按 repo 删；含 StockValue.after_create 自动写的入库 ledger）
  n += RepositoryLedgerRecord.where(repository_id: repo_ids).delete_all
  # 中间表 mmrr
  n += MyModuleRepositoryRow.where(repository_row_id: row_ids).delete_all
  # Row
  n += RepositoryRow.where(repository_id: repo_ids).delete_all
  # Repository 本身
  n += repos.delete_all
  n
end

if ROLLBACK
  n = rollback_seed(team, proj_pp)
  puts "== 已回滚 _seed_ 库存 + 关联 ledger + mmrr：共 #{n} 行"
  puts '== 原生表结构零改动（脚本不 ALTER 任何表）'
  exit 0
end

# ---- 1) 建两个 Repository（绑原生模板）----
chem_repo = Repository.where(team_id: team.id, name: '_seed_ 化学品与试剂库存').first_or_initialize
chem_repo.assign_attributes(
  created_by: admin,
  archived: false,
  repository_template_id: chem_tmpl.id
)
chem_repo.save!
puts "==> Repository (化学品与试剂库存，模板 ##{chem_tmpl.id}) ##{chem_repo.id}"

equip_repo = Repository.where(team_id: team.id, name: '_seed_ 设备库存').first_or_initialize
equip_repo.assign_attributes(
  created_by: admin,
  archived: false,
  repository_template_id: equip_tmpl.id
)
equip_repo.save!
puts "==> Repository (设备库存，模板 ##{equip_tmpl.id}) ##{equip_repo.id}"

# ---- 2) 每个 Repository 建「库存数量」Column + UnitItem（kg / 次）----
# 注：本次只建 Stock 列（其他模板列按需后续补）；库存已绑模板，UI 层能识别形态
def ensure_stock_column!(repo:, admin:)
  col = RepositoryColumn.where(repository_id: repo.id, data_type: 'RepositoryStockValue').first_or_initialize
  col.assign_attributes(name: '_seed_ 库存数量', created_by: admin)
  col.save!
  col
end

chem_col = ensure_stock_column!(repo: chem_repo, admin: admin)
chem_unit = RepositoryStockUnitItem.where(repository_column_id: chem_col.id, data: 'kg').first_or_initialize
chem_unit.assign_attributes(created_by: admin, last_modified_by: admin)
chem_unit.save!
puts "==> RepositoryColumn(化学品, stock) ##{chem_col.id} + UnitItem(kg) ##{chem_unit.id}"

equip_col = ensure_stock_column!(repo: equip_repo, admin: admin)
equip_unit = RepositoryStockUnitItem.where(repository_column_id: equip_col.id, data: '台次').first_or_initialize
equip_unit.assign_attributes(created_by: admin, last_modified_by: admin)
equip_unit.save!
puts "==> RepositoryColumn(设备, stock) ##{equip_col.id} + UnitItem(台次) ##{equip_unit.id}"

# ---- 3) RepositoryRow + RepositoryCell 多态挂载（用原生 RepositoryCell.create_with_value! 工厂）----
# ⚠ 关键 1：RepositoryStockValue.validates :repository_cell, presence: true —— 必须 cell+value 同步建
# ⚠ 关键 2：原生 RepositoryStockValue.new_with_payload 内部用 *混合 key*：
#     - payload[:amount]                  (symbol)  ← 必须
#     - payload['unit_item_id']           (string)  ← 必须（symbol 形式会被 .find_by(id:) 找不到 → 静默 nil）
#     - payload[:low_stock_threshold]     (symbol)
def make_row_with_stock!(repo:, col:, unit_item:, name:, unit_price:, amount:, admin:)
  row = RepositoryRow.where(repository_id: repo.id, name: name).first_or_initialize
  row.assign_attributes(
    created_by: row.created_by || admin, last_modified_by: admin,
    archived: false, unit_price: unit_price
  )
  row.save!

  # 幂等：若已有 cell，跳过 create_with_value! 直接修 sv 的 unit_item
  existing_cell = RepositoryCell.where(repository_row_id: row.id, repository_column_id: col.id).first
  if existing_cell
    sv = existing_cell.value
    if sv.respond_to?(:repository_stock_unit_item_id) && sv.repository_stock_unit_item_id.nil?
      sv.update_columns(repository_stock_unit_item_id: unit_item.id, amount: amount) # skip validations
    elsif sv.respond_to?(:amount=) && sv.amount.to_d != amount.to_d
      sv.update_column(:amount, amount)
    end
    return [row, sv]
  end

  cell = RepositoryCell.create_with_value!(
    row, col,
    { amount: amount,
      'unit_item_id' => unit_item.id,
      low_stock_threshold: 0 },
    admin
  )
  [row, cell.value]
end

pp_row,   pp_sv   = make_row_with_stock!(repo: chem_repo, col: chem_col, unit_item: chem_unit,
                                         name: '_seed_ PP 基料 K8003',          unit_price: 350, amount: 120, admin: admin)
poe_row,  poe_sv  = make_row_with_stock!(repo: chem_repo, col: chem_col, unit_item: chem_unit,
                                         name: '_seed_ POE 增韧剂 8150',         unit_price: 420, amount: 45,  admin: admin)
talc_row, talc_sv = make_row_with_stock!(repo: chem_repo, col: chem_col, unit_item: chem_unit,
                                         name: '_seed_ 滑石粉 TYT-777A',         unit_price: 180, amount: 8,   admin: admin)

dsc_row,  dsc_sv    = make_row_with_stock!(repo: equip_repo, col: equip_col, unit_item: equip_unit,
                                          name: '_seed_ DSC 差示扫描量热',       unit_price: 600, amount: 0, admin: admin)
tens_row, tens_sv  = make_row_with_stock!(repo: equip_repo, col: equip_col, unit_item: equip_unit,
                                          name: '_seed_ 万能材料试验机（拉伸）', unit_price: 200, amount: 0, admin: admin)

puts "==> RepositoryRow × 5 + StockValue × 5 + RepositoryCell × 5"

# ---- 4) MyModuleRepositoryRow（中间表，stock_consumption 用 update_column 置 0 跳过扣库存钩子）----
def make_mmrr!(my_module:, row:, user:, admin:)
  rec = MyModuleRepositoryRow.where(my_module_id: my_module.id, repository_row_id: row.id).first_or_initialize
  rec.assigned_by = user || admin
  rec.repository_stock_unit_item_id = nil
  rec.save! if rec.new_record?
  rec.update_column(:stock_consumption, 0) if rec.stock_consumption.nil?
  rec
end

mmrr_pp   = make_mmrr!(my_module: my_module, row: pp_row,   user: admin, admin: admin)
mmrr_poe  = make_mmrr!(my_module: my_module, row: poe_row,  user: admin, admin: admin)
mmrr_dsc  = make_mmrr!(my_module: my_module, row: dsc_row,  user: admin, admin: admin)
mmrr_tens = make_mmrr!(my_module: my_module, row: tens_row, user: admin, admin: admin)
puts "==> MyModuleRepositoryRow × 4（任务-库存关联）"

# ---- 5) 出库 LedgerRecord（reference=mmrr，amount 负）----
# ⚠ repository_ledger_records 没有 repository_id 列 —— 通过 repository_stock_value_id 关联到库存；
#   用户/项目从 my_module_references JSONB 拿（模型级硬校验必须含 project_id）
def make_out_ledger!(sv:, mmrr:, amount:, unit_price:, user:,
                     my_module_id:, project_id:, experiment_id:, team_id:, days_ago:)
  RepositoryLedgerRecord.create!(
    repository_stock_value: sv,
    reference: mmrr,
    amount: -amount.abs,
    balance: -amount.abs,
    unit: nil,
    user: user,
    my_module_references: {
      project_id: project_id, experiment_id: experiment_id,
      my_module_id: my_module_id, team_id: team_id
    },
    unit_price: unit_price,
    created_at: days_ago.days.ago
  )
end

make_out_ledger!(sv: pp_sv,   mmrr: mmrr_pp,   amount: 20, unit_price: 350, user: admin,
                 my_module_id: my_module.id, project_id: proj_pp.id, experiment_id: exp.id, team_id: team.id, days_ago: 22)
make_out_ledger!(sv: poe_sv,  mmrr: mmrr_poe,  amount: 5,  unit_price: 420, user: admin,
                 my_module_id: my_module.id, project_id: proj_pp.id, experiment_id: exp.id, team_id: team.id, days_ago: 37)
make_out_ledger!(sv: dsc_sv,  mmrr: mmrr_dsc,  amount: 2,  unit_price: 600, user: admin,
                 my_module_id: my_module.id, project_id: proj_pp.id, experiment_id: exp.id, team_id: team.id, days_ago: 27)
make_out_ledger!(sv: tens_sv, mmrr: mmrr_tens, amount: 3,  unit_price: 200, user: admin,
                 my_module_id: my_module.id, project_id: proj_pp.id, experiment_id: exp.id, team_id: team.id, days_ago: 30)
puts "==> 出库 LedgerRecord × 4（含 2 行物资 + 2 行设备/服务）"
puts "    (入库 LedgerRecord × 5 由 StockValue.after_create 自动写入，无需手动 create)"

# ---- 自证 ----
sv_ids = [pp_sv.id, poe_sv.id, talc_sv.id, dsc_sv.id, tens_sv.id]
puts
puts "==> 汇总："
puts "    Repository (化学品) ##{chem_repo.id} (模板 ##{chem_tmpl.id})"
puts "    Repository (设备)   ##{equip_repo.id} (模板 ##{equip_tmpl.id})"
puts "    RepositoryColumn(stock) × #{RepositoryColumn.where(repository_id: [chem_repo.id, equip_repo.id], data_type: 'RepositoryStockValue').count}"
puts "    RepositoryRow × #{RepositoryRow.where(repository_id: [chem_repo.id, equip_repo.id]).count}"
puts "    RepositoryStockValue × #{RepositoryStockValue.where(id: sv_ids).count}"
puts "    RepositoryCell(stock 多态) × #{RepositoryCell.where(repository_row_id: RepositoryRow.where(repository_id: [chem_repo.id, equip_repo.id]).pluck(:id), value_type: 'RepositoryStockValue').count}"
puts "    LedgerRecord 总数（5 入 + 4 出） = #{RepositoryLedgerRecord.where(repository_stock_value_id: sv_ids).count}"
puts "    项目花费可聚合金额（按 my_module_references->>'project_id'）："
out_total = RepositoryLedgerRecord.where(repository_stock_value_id: sv_ids, reference_type: 'MyModuleRepositoryRow').sum('unit_price * ABS(amount)')
puts "        = ¥ #{out_total.to_i}（mmrr ledger；本 seed 只覆了 1 项目）"

# ---- 6) 多项目花费聚合（写 eln_ui_project_cost_items cache，让「项目花费」tab 多项目呈现）----
# ⚠ ProjectCostItem 表结构：一行 = 一个类别的汇总行（category/source/basis/amount/position）
#   单项目 mmrr ledger 聚合只能出 1 行，故用 cache 表补 4 项目（与 V1.22 画布口径 ¥44,640 对齐）
#   source 字段写「_seed_<备注>」，cleanup 脚本走 source LIKE '_seed_%' 即可定位
cost_data = [
  ['高温硅胶研究',     '材料',     '_seed_累计（V1.22 画布口径）', 'RepositoryRow.unit_price × 累计入库', 12400, 1],
  ['高温硅胶研究',     '测试表征', '_seed_累计（V1.22 画布口径）', 'RepositoryRow.unit_price × 服务行', 3600,  2],
  ['PP 配方优化（主）', '材料',     '_seed_累计（V1.22 画布口径）', 'RepositoryRow.unit_price × 累计入库', 9180,  1],
  ['PP 配方优化（主）', '测试表征', '_seed_累计（V1.22 画布口径）', 'RepositoryRow.unit_price × 服务行', 6200,  2],
  ['阻燃 PP 开发',     '材料',     '_seed_累计（V1.22 画布口径）', 'RepositoryRow.unit_price × 累计入库', 5260,  1],
  ['阻燃 PP 开发',     '测试表征', '_seed_累计（V1.22 画布口径）', 'RepositoryRow.unit_price × 服务行', 2400,  2],
  ['高抗冲 PP 改性',   '材料',     '_seed_累计（V1.22 画布口径）', 'RepositoryRow.unit_price × 累计入库', 4000,  1],
  ['高抗冲 PP 改性',   '测试表征', '_seed_累计（V1.22 画布口径）', 'RepositoryRow.unit_price × 服务行', 1600,  2]
]
cost_total = 0
cost_data.each do |name, cat, src, basis, amount, position|
  proj = ::Project.where(team_id: team.id, name: name).first_or_create do |p|
    p.created_by = admin
    p.archived = false
    p.save!
  end
  cost = Scinote::ElnUi::ProjectCostItem.where(project_id: proj.id, category: cat, source: src).first_or_initialize
  cost.assign_attributes(
    amount: amount, basis: basis, position: position
  ); cost.save!
  cost_total += amount
end
puts "==> ProjectCostItem × 8（4 项目 × {材料, 测试表征}），总额 ¥#{cost_total}"
puts
puts "==> 完成。可访问：/eln_res_center (4 tab 都有真数据)"
puts "==> 回滚：bin/rails runner /tmp/seed_inventory.rb --rollback"
exit 0