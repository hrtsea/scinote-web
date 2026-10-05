# frozen_string_literal: true
#
# ELN UI —— 资源中心 5 页签 + 申请详情 数据装配
#   (Scinote::ElnUi::ResCenterPayload + ResApplyDetailPayload)
#
# 守 3 件事：
#   1. inventory / consume 走原生 Repository + RepositoryLedgerRecord 真库
#      （「Inventories」即原生库存模板体系 —— 用户指令 2026-10-04）；
#      台账页签不再自绘 materials 表，只列原生库存库入口（完全采用原生页承载）；
#   2. apply 走 addon 自有表；**cost 与 consume 同源**（Ledger 任务消耗行聚合，
#      2026-10-04 用户指令「花费必须与出入库/消耗明细对应上」，规格 V1.21 L852/L854；
#      无原生对应时必须显式空集，不许编演示值）；
#   3. unit_price 快照：消耗链路（decorator）落 LedgerRecord.unit_price，花费按
#      快照价核算（SCN-RES-COST-2）；设备模板行不计花费（SCN-RES-COST-6）。

require_relative 'test_helper'

class ElnUiResCenterTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories # 库存/流水/任务消耗工厂（eln_ui_factories.rb，与项目详情测试共享）

  # ============================================================
  # 资源中心：5 tab
  # ============================================================

  # ① inventory tab：repositories 入口来自原生真库（台账完全采用原生 Inventories）
  def test_inventory_block_lists_native_repositories
    scene = build_scene!
    team = scene[:team]
    repo = make_active_repository!(team: team, name: 'PP 原材料库', creator: scene[:creator])
    make_repository_row!(repository: repo, name: 'PP 基料 K8003',
                         unit_price: 350.0, amount: 120, unit: 'kg',
                         creator: scene[:creator])

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    repos = body[:inventory][:repositories]
    assert_equal 1, repos.size, '真库存库数 = 真库数'
    r = repos.first
    assert_equal repo.id, r[:id], '入口 id = 原生 Repository.id（前端直达 /repositories/:id）'
    assert_equal 'PP 原材料库', r[:name], '名称取 Repository.name'
    assert_equal 1, r[:rowsCount], '条目数取未归档 RepositoryRow 数'
  end

  # ①.2 ledger tab：records 来自原生真库（出入库记录单列页签）
  def test_ledger_block_reads_native_ledger_records
    scene = build_scene!
    team = scene[:team]
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, name: 'PP 基料 K8003',
                               unit_price: 350.0, amount: 120, unit: 'kg',
                               creator: scene[:creator])
    sv  = RepositoryStockValue.joins(:repository_cell)
                              .where(repository_cells: { repository_row_id: row.id }).first
    make_ledger_record!(repository: repo, stock_value: sv,
                        amount: -20, balance: 100, unit: 'kg',
                        user: scene[:creator], unit_price: 350.0)

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    records = body[:ledger][:records]
    # ⚠ create_with_value! 建 StockValue 时原生 after_create 会自动写一条「入库」流水，
    #   所以 records ≥ 1 + 我们显式建的 1 条出库。断言盯「出库行在流水里」，
    #   不盯总数（总数随原生入库行为浮动）。
    out_rec = records.find { |r| r[:type] == '出库' }
    refute_nil out_rec, '显式建的出库行必须在出入库流水里'
    assert_equal 'PP 基料 K8003', out_rec[:name], '名称走 EAV 反查 RepositoryRow'
    assert_includes out_rec[:price], '350', '快照单价取 LedgerRecord.unit_price'
  end

  # ② consume tab：reference_type = MyModuleRepositoryRow 的 Ledger 行
  def test_consume_block_reads_task_consumption_records
    scene = build_scene!
    team = scene[:team]
    project = scene[:project]
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, unit_price: 350.0, unit: 'kg',
                               creator: scene[:creator])
    mmr = make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                         assigned_by: scene[:creator], amount: 20, unit: 'kg')

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    rows = body[:consume][:rows]
    assert_equal 1, rows.size
    row0 = rows.first
    assert_equal row.name, row0[:name], '消耗明细行名 = RepositoryRow.name'
    assert_includes row0[:qty], '20', '数量取 my_module_repository_rows.amount 绝对值'
    assert_includes row0[:qty], 'kg', '单位跟随 MMR'
    assert_equal project.name, row0[:project], '关联项目从 my_module_references.project_id 取'
  end

  # ③ unit_price 快照：LedgerRecord 必须带 unit_price，否则金额算法无从落地
  def test_ledger_record_unit_price_snapshot_is_persisted
    scene = build_scene!
    team = scene[:team]
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, unit_price: 350.0, unit: 'kg',
                               creator: scene[:creator])
    # ⚠ RepositoryStockValue 没有 repository_row_id 列 —— 行挂在 cell 上，
    #   要走 joins(:repository_cell) 才能按 row 找（payload 里也是这么写的）
    sv  = RepositoryStockValue.joins(:repository_cell)
                               .where(repository_cells: { repository_row_id: row.id }).first
    rec = make_ledger_record!(repository: repo, stock_value: sv,
                              amount: -20, balance: 100, unit: 'kg',
                              user: scene[:creator], unit_price: 350.0)

    # 关键：列存在、可写、读出来和入库值一致
    refute_nil rec, 'LedgerRecord 必须可创建'
    assert_equal 350.0, rec.reload.unit_price.to_f, 'unit_price 快照列必须可读'
    assert rec.respond_to?(:unit_price), '必须存在 unit_price 方法（additive 列已加）'
  end

  # ④ 资源申请 tab：addon 自有表，无原生对应 → 无数据时**显式空数组**
  def test_apply_block_returns_explicit_empty_when_no_data
    scene = build_scene!
    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: scene[:team])

    refute_nil body[:apply], 'apply 键必须存在（缺键 = 前端 fallback 到原型演示值）'
    assert_equal [], body[:apply][:rows], '无申请单 → 显式空数组（不返回 nil / 不编演示值）'
  end

  # 资源申请：有数据时按项目 + 团队范围过滤
  def test_apply_block_lists_apps_for_team_scope
    scene = build_scene!
    project = scene[:project]
    app = make_resource_application!(project: project, requestor: scene[:creator],
                                     no: 'SQ-2026-9999', status: 'submitted')

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: scene[:team])

    assert_equal 1, body[:apply][:rows].size
    row = body[:apply][:rows].first
    assert_equal 'SQ-2026-9999', row[:no], '业务编号原样透传'
    assert_equal '待审批', row[:status], 'status 枚举映射到中文 label'
    assert_equal scene[:creator].full_name.to_s, row[:user], 'requestor 名 = 真用户全名'
  end

  # ⑤ 项目花费 tab：真源 = Ledger 任务消耗行（规格 V1.21 L852/L854），无数据 → 显式空
  def test_cost_block_returns_explicit_empty_when_no_data
    scene = build_scene!
    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: scene[:team])

    refute_nil body[:cost], 'cost 键必须存在'
    assert_equal 4, body[:cost][:stats].size, 'stats 永远 4 卡（语义稳定）'
    assert_equal [], body[:cost][:byProject], '无消耗行 → byProject 空'
    assert_equal [], body[:cost][:byMember], '无消耗行 → byMember 空'
    assert_equal '¥0', body[:cost][:stats].first[:value], '无总额 → ¥0（不编演示值）'
    assert_equal true, body[:cost][:reconciliation][:consistent], '无数据时对账恒真'
  end

  # 项目花费：Ledger 消耗行按项目聚合（金额 = |amount| × 快照单价）+ 笔数 + 占比
  def test_cost_block_groups_by_project_and_computes_share
    scene = build_scene!
    team = scene[:team]
    project = scene[:project]
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, name: 'PP 基料 K8003',
                               unit_price: 350.0, amount: 100, unit: 'kg',
                               creator: scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                   assigned_by: scene[:creator], amount: 20, unit: 'kg')

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    recon = body[:cost][:reconciliation]
    assert_equal 1, recon[:detailMaterialRows], '对账块：明细表物资行数'
    assert_equal 1, recon[:ledgerMaterialRows], '对账块：Ledger 侧消耗行数（一一对应）'
    by_proj = body[:cost][:byProject]
    assert_equal 1, by_proj.size
    r = by_proj.first
    assert_equal project.name, r[:name]
    assert_equal '¥7,000', r[:total], '金额 = |amount| × 快照单价（20 × 350）'
    assert_equal '¥7,000', r[:material]
    assert_equal '¥0', r[:service], '服务执行：本例无服务明细行（服务走明细表，不写 Ledger）'
    assert_equal 1, r[:count], '消耗笔数列（对账可视）'
    assert_equal '100%', r[:ratio]
    assert_equal '¥7,000', body[:cost][:stats].first[:value]
    assert_equal true, recon[:consistent], '明细行数 == 流行数 且金额同值（一一对应）'
  end

  # 跨项目聚合 + 按金额降序
  def test_cost_block_sorts_by_total_descending
    scene = build_scene!
    team = scene[:team]
    proj1 = scene[:project]
    proj2 = make_project!(team: team, creator: scene[:creator], name: 'B 项目')
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, unit_price: 100.0, amount: 500,
                               unit: 'kg', creator: scene[:creator])
    task1 = build_task_for(scene)
    # ⚠ task2 必须**真的挂在 proj2 下**（原来 build_task_for(scene) 造的是 proj1 的实验，
    #   于是两个项目都归到 proj1，byProject 只有 1 项 → 断言 2 永远失败）。
    #   byProject 的语义是「按 Ledger 行 my_module_references.project_id 分组聚合」，
    #   没有消耗行的项目本就不出现 —— 要验跨项目，前提是两个项目都得有花费。
    exp2 = make_experiment!(project: proj2, creator: scene[:creator])
    task2 = make_task!(experiment: exp2, creator: scene[:creator])
    make_my_module_repository_row!(my_module: task1, repository_row: row,
                                   assigned_by: scene[:creator], amount: 100)
    make_my_module_repository_row!(my_module: task2, repository_row: row,
                                   assigned_by: scene[:creator], amount: 30)

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    by_proj = body[:cost][:byProject]
    assert_equal 2, by_proj.size, '两个项目各有一笔消耗 → byProject 归出 2 项'
    # 排序：proj1 消耗 100×100=10,000 > proj2 30×100=3,000
    assert by_proj.first[:total].gsub(/[^\d]/, '').to_i >= by_proj.last[:total].gsub(/[^\d]/, '').to_i
    assert_equal 1, by_proj.first[:count], '每项目 1 笔'
    # byProject 元素字段是 id / name / count / material / service / total / ratio
    # （见 res_center_payload.rb#by_project_block），不是 projectId。
    assert_equal proj1.id, by_proj.first[:id], '金额大的排第一（proj1 = 10,000）'
    assert_equal proj2.id, by_proj.last[:id], '金额小的排第二（proj2 = 3,000）'
  end

  # ★ 花费与出入库/消耗明细三方同源：cost 累计 == consume totalAmount == Σ|amount|×价
  def test_cost_total_matches_consume_tab_amount
    scene = build_scene!
    team = scene[:team]
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, unit_price: 250.0, amount: 100,
                               unit: 'kg', creator: scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                   assigned_by: scene[:creator], amount: 8)

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    recon = body[:cost][:reconciliation]
    assert_equal '¥2,000', recon[:detailMaterialTotal], '明细表物资金额（花费归集唯一对外数据源）'
    assert_equal recon[:detailMaterialTotal], recon[:ledgerMaterialTotal],
                 '明细金额 == Ledger 同口径金额（spec L106 同源同值）'
    assert_equal body[:consume][:totalAmount], recon[:detailMaterialTotal],
                 '对账块金额 = 消耗/执行明细页签合计（同一张表）'
    assert_equal '¥2,000', recon[:detailMaterialTotal], '8 × 250 = 2,000'
    assert_equal true, recon[:consistent]
  end

  # ★ SCN-RES-COST-2：快照单价防改价 —— 花费用流水行单价，与物料当前价无关
  def test_cost_uses_ledger_snapshot_price_not_current_row_price
    scene = build_scene!
    team = scene[:team]
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, unit_price: 350.0, amount: 100,
                               unit: 'kg', creator: scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                   assigned_by: scene[:creator], amount: 20)
    # 出库之后物料改价：快照应不受影响
    row.update_column(:unit_price, 999.0)

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    assert_equal '¥7,000', body[:cost][:byProject].first[:total],
                 '必须按出库时快照价 350 算（20×350），不能吃改价后的 999'
  end

  # ★ SCN-RES-COST-4：入库不计花费 + 还回冲减 —— 花费聚合只认任务消耗行：
  #   自动入库行（Inventory ref、正 amount）进不了 cost；任务行负 amount（还回）冲减
  def test_cost_excludes_inbound_rows_and_refunds_reduce_cost
    scene = build_scene!
    team = scene[:team]
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, unit_price: 100.0, amount: 100,
                               unit: 'kg', creator: scene[:creator])
    # make_repository_row! 的 create_with_value! 已自动写 1 条入库流水（amount=100）
    mmr = make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                         assigned_by: scene[:creator], amount: 10)
    # 任务内还回 3（stock_consumption 10 → 7，delta = -3 → 原生还回行）
    mmr.update!(stock_consumption: 7)

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    recon = body[:cost][:reconciliation]
    assert_equal 2, recon[:detailMaterialRows], '消耗 1 笔 + 还回 1 笔（自动入库行不算）'
    assert_equal '¥700', recon[:detailMaterialTotal], '花费 = (10 − 3) × 100，入库不计'
    assert_equal true, recon[:consistent], '还回行的明细行与流水行同步登记，对账仍对应'
  end

  # ★ SCN-RES-COST-6：设备模板库存不计入项目花费（按模板归属排除，非依赖 Stock 缺失）
  def test_cost_excludes_equipment_template_rows
    scene = build_scene!
    team = scene[:team]
    # ⚠ RepositoryTemplate 有 team_id 且必填 —— create! 必须给 team，
    #   否则 'Validation failed: Team must exist'（本轮真机 minitest 抓到的）。
    #   名字必须用 RepositoryTemplate.equipment.name：res_center_payload 的
    #   team_repo_ids 就是按这个名字把设备模板库存整库排除的（SCN-RES-COST-6）。
    tmpl = ::RepositoryTemplate.create!(name: ::RepositoryTemplate.equipment.name, team: team)
    repo = make_active_repository!(team: team, creator: scene[:creator],
                                   name: '设备库', template: tmpl)
    row = make_repository_row!(repository: repo, unit_price: 500.0, amount: 100,
                               unit: '次', creator: scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                   assigned_by: scene[:creator], amount: 2)

    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: team)

    recon = body[:cost][:reconciliation]
    assert_equal 0, recon[:detailMaterialRows], '设备模板行不计花费（明细侧 0 行）'
    assert_equal 0, recon[:ledgerMaterialRows], '设备模板行不计花费（Ledger 侧 0 行）'
    assert_equal '¥0', recon[:detailMaterialTotal], '金额 ¥0'
    assert_equal true, recon[:consistent], '两侧同为 0 行 ¥0 —— 一致'
    assert_equal [], body[:cost][:byProject], '被排除的行不进 byProject'
  end

  # ★ 快照单价补写 decorator：原生 deduct_stock_balance 不写 unit_price（列默认 0），
  #   消耗链路完成后必须把 RepositoryRow.unit_price 补写进流水行 —— 花费核算的真源
  def test_consume_chain_writes_unit_price_snapshot
    scene = build_scene!
    team = scene[:team]
    repo = make_active_repository!(team: team, creator: scene[:creator])
    row = make_repository_row!(repository: repo, name: 'POE 8150',
                               unit_price: 420.0, amount: 100, unit: 'kg',
                               creator: scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                   assigned_by: scene[:creator], amount: 5)

    rec = RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow')
                                .order(id: :desc).take
    refute_nil rec, 'MMR 消耗必须写流水行'
    assert_equal 5.0, rec.amount.to_f, '任务消耗行 amount 为正（原生符号语义）'
    assert_equal 420.0, rec.unit_price.to_f,
                 '快照单价必须由 decorator 补写（原生 deduct 不写，列默认 0）'
  end

  # ★ spec L106：物资消耗链路必须**同步登记一行**明细（与 Ledger 一一对应、同快照单价，
  #   不得单独录入造成双写失真）。登记动作挂在 decorator 末尾，本例验证它真的落库了。
  def test_consume_chain_registers_material_row_into_detail_table
    scene = build_scene!
    team = scene[:team]
    creator = scene[:creator]
    repo = make_active_repository!(team: team, creator: creator)
    row = make_repository_row!(repository: repo, name: 'PP 基料 K8003',
                               unit_price: 350.0, amount: 100, unit: 'kg', creator: creator)
    make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                   assigned_by: creator, amount: 20)

    ledger = RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow')
                                   .order(id: :desc).take
    detail = Scinote::ElnUi::ConsumeRecord.find_by(source_type: 'RepositoryLedgerRecord',
                                                   source_id: ledger.id)
    refute_nil detail, 'spec L106：消耗链路必须在明细表同步登记一行'
    assert_equal 'material', detail.kind
    assert_equal 'PP 基料 K8003', detail.name
    assert_equal 20.0, detail.quantity.to_f
    assert_equal 350.0, detail.unit_price.to_f, '同快照单价（与 Ledger 行同源）'
    assert_equal 7_000.0, detail.amount.to_f, '金额 = 数量 × 单价快照'

    # 幂等：再跑一次登记（模拟 decorator 重入 / 回填重复调用）不产生重复行
    Scinote::ElnUi::ConsumeRecord.sync_material_from_ledger!(ledger: ledger)
    assert_equal 1, Scinote::ElnUi::ConsumeRecord.where(source_type: 'RepositoryLedgerRecord',
                                                        source_id: ledger.id).count,
                 '唯一索引 + find_or_initialize_by：重复登记不增行'
  end

  # ★ spec L107/L108：服务执行走明细表（不写 Ledger）并计入花费 —— OPEN-9 从 ¥0 占位
  #   换成真值；按 L109 只有 settled（验收通过）才计入。
  def test_cost_includes_service_rows_from_detail_table
    scene = build_scene!
    team = scene[:team]
    creator = scene[:creator]

    make_consume_record!(project: scene[:project], user: creator, kind: 'service',
                         name: 'DSC 差示扫描量热', quantity: 2, unit: '次',
                         unit_price: 600, amount: 1_200, result_status: 'settled',
                         source_type: 'Scinote::ElnUi::ResourceApplication', source_id: 77_770_001)

    body = Scinote::ElnUi::ResCenterPayload.call(user: creator, team: team)

    stats = body[:cost][:stats].each_with_object({}) { |s, h| h[s[:label]] = s[:value] }
    assert_equal '¥1,200', stats['服务执行'], '服务执行取明细表 service 行真值（不再是 ¥0 占位）'
    assert_equal '¥1,200', stats['累计花费'], '累计花费 = 物资 + 服务'
    assert_equal '¥0', body[:cost][:reconciliation][:detailMaterialTotal], '本例无物资明细行'
    # 消耗/执行明细页签两类行同表展示（spec L105）
    kinds = body[:consume][:rows].map { |r| r[:type] }
    assert_equal ['服务'], kinds, '明细页签出现服务行（物资+服务同一张表）'
    svc = body[:consume][:rows].first
    assert_equal 'DSC 差示扫描量热', svc[:name]
    assert_equal '¥1,200', svc[:amount]
    assert_equal '已结算', svc[:status], 'settled → 已结算（spec L109 计入花费）'
    # 服务不写 Ledger：本例不该有任务消耗流水行
    assert_equal 0, RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow').count,
                 '服务行不走 Ledger（spec L107）'
  end

  # ★ spec L109 验收闸门：pending_acceptance 的服务行**不计花费**，转 settled 才计入。
  def test_pending_acceptance_service_row_not_counted
    scene = build_scene!
    team = scene[:team]
    creator = scene[:creator]

    make_consume_record!(project: scene[:project], user: creator, kind: 'service',
                         name: '万能材料试验机（拉伸）', quantity: 3, unit: '次',
                         unit_price: 200, amount: 600, result_status: 'pending_acceptance',
                         source_type: 'Scinote::ElnUi::ResourceApplication', source_id: 77_770_002)
    make_consume_record!(project: scene[:project], user: creator, kind: 'service',
                         name: 'DSC 差示扫描量热', quantity: 2, unit: '次',
                         unit_price: 600, amount: 1_200, result_status: 'settled',
                         source_type: 'Scinote::ElnUi::ResourceApplication', source_id: 77_770_003)

    body = Scinote::ElnUi::ResCenterPayload.call(user: creator, team: team)
    stats = body[:cost][:stats].each_with_object({}) { |s, h| h[s[:label]] = s[:value] }

    assert_equal '¥1,200', stats['服务执行'], '只计 settled 行（1,200），pending 的 600 不计'
    assert_equal '¥1,200', stats['累计花费']
    # 待验收行仍在明细表（展示用），只是不计花费
    assert_equal 2, body[:consume][:rows].size, '两条服务明细都在明细页签里'
    statuses = body[:consume][:rows].map { |r| r[:status] }
    assert_includes statuses, '待验收', 'pending_acceptance 行展示为「待验收」（不计花费但可见）'
    assert_includes statuses, '已结算', 'settled 行展示为「已结算」'
  end

  # ★ 对账闸门真会假：明细行与流水行数量对不上时必须报不一致（历史行漏登记会在这暴露）
  def test_reconciliation_flags_missing_detail_rows
    scene = build_scene!
    team = scene[:team]
    creator = scene[:creator]
    repo = make_active_repository!(team: team, creator: creator)
    row = make_repository_row!(repository: repo, unit_price: 200.0, amount: 100,
                               unit: 'kg', creator: creator)
    make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                   assigned_by: creator, amount: 7)

    body = Scinote::ElnUi::ResCenterPayload.call(user: creator, team: team)
    recon = body[:cost][:reconciliation]
    assert_equal 1, recon[:ledgerMaterialRows]
    assert_equal '¥1,400', recon[:ledgerMaterialTotal], '7 × 200 = 1,400（Ledger 侧）'
    assert_equal true, recon[:consistent], '正常登记时一一对应'

    # 人为制造缺口：删掉明细行（模拟回填漏跑 / 历史数据未登记）
    Scinote::ElnUi::ConsumeRecord.where(kind: 'material').delete_all

    body2 = Scinote::ElnUi::ResCenterPayload.call(user: creator, team: team)
    recon2 = body2[:cost][:reconciliation]
    assert_equal false, recon2[:consistent], '明细缺行 → 对账必须报不一致（闸门有效性）'
    assert_equal 0, recon2[:detailMaterialRows]
    assert_equal 1, recon2[:ledgerMaterialRows]
  end

  # ============================================================
  # 资源申请详情：单条详情
  # ============================================================

  def test_apply_detail_not_found_returns_flag
    body = Scinote::ElnUi::ResApplyDetailPayload.call(user: scene_user, team: scene_team, no: 'SQ-0000-0000')
    # 注：scene_user/scene_team 在 notFound 分支可不依赖
    assert_equal true, body[:notFound] || body[:forbidden],
                 '不存在的编号必须显式 notFound（不抛 500）'
  end

  def test_apply_detail_loads_real_application
    scene = build_scene!
    project = scene[:project]
    app = make_resource_application!(project: project, requestor: scene[:creator],
                                     no: 'SQ-2026-7777', status: 'group_approved')
    app.update!(group_reviewer: scene[:creator], group_approved_at: Time.current)

    body = Scinote::ElnUi::ResApplyDetailPayload.call(user: scene[:creator], team: scene[:team],
                                                      no: 'SQ-2026-7777')

    refute body[:notFound], '已存在申请单不能 notFound'
    refute body[:forbidden], '团队成员可见'
    assert_equal 'SQ-2026-7777', body[:application][:no]
    assert_equal '小组通过', body[:application][:statusLabel], '枚举 → 中文 label'
    assert_equal project.name, body[:application][:project][:name], '项目名取真库'
    refute_empty body[:timeline], 'timeline 必有至少 submitted 事件'
  end

  # ============================================================
  # 资源申请写流程（OPEN-10 · REQ-RES-APPROVE 二段式审批）
  # ============================================================

  # 提交：requestor 本人 draft → submitted，submitted_at 落值
  def test_submit_by_requestor_moves_draft_to_submitted
    scene = build_scene!
    app = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                     no: 'SQ-2026-8801', status: 'draft')

    result = Scinote::ElnUi::ResourceApplicationWorkflow.call(
      user: scene[:creator], team: scene[:team], no: app.no, type: 'submit'
    )

    assert result[:ok], "submit 应成功：#{result[:error]}"
    assert_equal 'submitted', result[:status]
    assert_equal '待审批', result[:statusLabel], '枚举映射中文 label'
    refute_nil app.reload.submitted_at, 'submitted_at 必须落值'
  end

  # 初审：同队非本人 submitted → group_approved，reviewer 落值
  def test_approve_group_by_teammate_records_reviewer
    scene = build_scene!
    app = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                     no: 'SQ-2026-8802', status: 'submitted')
    mate = make_workflow_user!

    result = Scinote::ElnUi::ResourceApplicationWorkflow.call(
      user: mate, team: scene[:team], no: app.no, type: 'approve_group'
    )

    assert result[:ok], "approve_group 应成功：#{result[:error]}"
    assert_equal 'group_approved', app.reload.status
    assert_equal mate.id, app.group_reviewer_id, '初审人必须留痕'
    refute_nil app.reload.group_approved_at
  end

  # 终审：group_approved → project_approved，reviewer 落值
  def test_approve_project_after_group_records_reviewer
    scene = build_scene!
    app = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                     no: 'SQ-2026-8803', status: 'group_approved')
    mate = make_workflow_user!

    result = Scinote::ElnUi::ResourceApplicationWorkflow.call(
      user: mate, team: scene[:team], no: app.no, type: 'approve_project'
    )

    assert result[:ok], "approve_project 应成功：#{result[:error]}"
    assert_equal 'project_approved', app.reload.status
    assert_equal mate.id, app.project_reviewer_id, '终审人必须留痕'
  end

  # 驳回：submitted 阶段 → rejected，reviewer 落值 + 原因进 note
  def test_reject_from_submitted_records_reviewer_and_reason
    scene = build_scene!
    app = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                     no: 'SQ-2026-8804', status: 'submitted')
    mate = make_workflow_user!

    result = Scinote::ElnUi::ResourceApplicationWorkflow.call(
      user: mate, team: scene[:team], no: app.no, type: 'reject', reason: '库存不足'
    )

    assert result[:ok], "reject 应成功：#{result[:error]}"
    assert_equal 'rejected', app.reload.status
    assert_equal mate.id, app.group_reviewer_id, 'submitted 阶段驳回记到初审人字段'
    assert_includes app.reload.note, '驳回原因：库存不足'
  end

  # 完成：project_approved → completed，completed_at 落值
  def test_complete_after_project_approval
    scene = build_scene!
    app = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                     no: 'SQ-2026-8805', status: 'project_approved')
    mate = make_workflow_user!

    result = Scinote::ElnUi::ResourceApplicationWorkflow.call(
      user: mate, team: scene[:team], no: app.no, type: 'complete'
    )

    assert result[:ok], "complete 应成功：#{result[:error]}"
    assert_equal 'completed', app.reload.status
    refute_nil app.reload.completed_at
  end

  # 负例：申请人本人不能审自己的单
  def test_requestor_cannot_approve_own_application
    scene = build_scene!
    app = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                     no: 'SQ-2026-8806', status: 'submitted')

    e = assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
      Scinote::ElnUi::ResourceApplicationWorkflow.call(
        user: scene[:creator], team: scene[:team], no: app.no, type: 'approve_group'
      )
    end
    assert_match(/同团队/, e.message)
    assert_equal 'submitted', app.reload.status, '被拒动作不得改变状态'
  end

  # 负例：状态错序一律拒绝（draft 直接终审 / 终态再驳回）
  def test_wrong_status_transition_is_refused
    scene = build_scene!
    draft = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                       no: 'SQ-2026-8807', status: 'draft')
    done  = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                       no: 'SQ-2026-8808', status: 'completed')
    mate = make_workflow_user!

    assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
      Scinote::ElnUi::ResourceApplicationWorkflow.call(
        user: mate, team: scene[:team], no: draft.no, type: 'approve_project'
      )
    end
    assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
      Scinote::ElnUi::ResourceApplicationWorkflow.call(
        user: mate, team: scene[:team], no: done.no, type: 'reject'
      )
    end
    assert_equal 'draft', draft.reload.status, '错序动作不得改变状态'
    assert_equal 'completed', done.reload.status, '错序动作不得改变状态'
  end

  # 负例：未知操作名拒绝（不落地任何变更）
  def test_unknown_type_is_refused
    scene = build_scene!
    app = make_resource_application!(project: scene[:project], requestor: scene[:creator],
                                     no: 'SQ-2026-8809', status: 'submitted')

    assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
      Scinote::ElnUi::ResourceApplicationWorkflow.call(
        user: scene[:creator], team: scene[:team], no: app.no, type: 'delete_everything'
      )
    end
    assert_equal 'submitted', app.reload.status
  end

  # ============================================================
  # 新建申请表单（SCN-RES-APPLY-1 · OPEN-10 收尾）
  # ============================================================

  # 表单直建草稿：编号自动生成 + 字段落位（items/note/requestor）
  def test_create_draft_generates_no_and_persists_fields
    scene = build_scene!
    count_before = Scinote::ElnUi::ResourceApplication.count

    result = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: scene[:creator], team: scene[:team],
      project_id: scene[:project].id, kind: 'material', name: 'PP 基料 K8003',
      qty: '20', unit: 'kg', unit_price: '350', purpose: '试制样品'
    )

    assert result[:ok], "create_draft 应成功：#{result[:error]}"
    assert_match(/\ASQ-\d{4}-\d{4}\z/, result[:no], '编号必须符合 SQ-YYYY-NNNN')
    assert_equal count_before + 1, Scinote::ElnUi::ResourceApplication.count, '必须真实落行'

    app = Scinote::ElnUi::ResourceApplication.find_by(no: result[:no])
    refute_nil app, '返回的编号必须能查到单据'
    assert_equal 'draft', app.status, '表单直建 → 草稿'
    assert_equal scene[:creator].id, app.requestor_id, 'requestor = 当前用户'
    assert_equal scene[:project].id, app.project_id
    assert_equal '试制样品', app.note, '用途进 note'
    item = app.item_list.first
    assert_equal 'material', item[:kind]
    assert_equal 'PP 基料 K8003', item[:name]
    assert_equal 20, item[:qty], '整数数量存 Integer（BigDecimal 落 jsonb 会变字符串）'
    assert_equal 'kg', item[:unit]
    assert_equal 350, item[:unit_price], '单价同样整数化'
  end

  # 编号递增：连建两单 → 序号严格 +1
  def test_create_draft_numbers_increment
    scene = build_scene!
    r1 = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: scene[:creator], team: scene[:team],
      project_id: scene[:project].id, kind: 'material', name: 'A', qty: '1'
    )
    r2 = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: scene[:creator], team: scene[:team],
      project_id: scene[:project].id, kind: 'service', name: 'B', qty: '2', unit: '次'
    )
    assert_equal r1[:no].succ, r2[:no], "连建两单编号必须严格 +1（#{r1[:no]} → #{r2[:no]}）"
  end

  # 负例：名称必填（空串 / 纯空格都算空）
  def test_create_draft_requires_name
    scene = build_scene!
    e = assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
      Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
        user: scene[:creator], team: scene[:team],
        project_id: scene[:project].id, kind: 'material', name: '   ', qty: '1'
      )
    end
    assert_match(/资源名称/, e.message)
    assert_equal 0, Scinote::ElnUi::ResourceApplication.where(project_id: scene[:project].id).count,
                   '校验失败不得落行'
  end

  # 负例：数量必须 > 0（0 / 空 / 负数都拦）
  def test_create_draft_requires_positive_qty
    scene = build_scene!
    ['0', '', '-5'].each do |qty|
      e = assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
        Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
          user: scene[:creator], team: scene[:team],
          project_id: scene[:project].id, kind: 'material', name: 'X', qty: qty
        )
      end
      assert_match(/数量/, e.message)
    end
    assert_equal 0, Scinote::ElnUi::ResourceApplication.where(project_id: scene[:project].id).count
  end

  # 负例：类型白名单（material | service 之外全拒）
  def test_create_draft_validates_kind
    scene = build_scene!
    e = assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
      Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
        user: scene[:creator], team: scene[:team],
        project_id: scene[:project].id, kind: 'equipment', name: 'X', qty: '1'
      )
    end
    assert_match(/资源类型/, e.message)
  end

  # 负例：跨团队项目拒绝（与 call 的团队口径一致）
  def test_create_draft_rejects_foreign_team_project
    scene = build_scene!
    other_user = make_workflow_user!
    other_team = Team.create!(name: "t2-#{SecureRandom.hex(3)}", created_by: other_user)
    foreign_project = make_project!(team: other_team, creator: other_user)

    e = assert_raises(Scinote::ElnUi::ResourceApplicationWorkflow::WorkflowError) do
      Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
        user: scene[:creator], team: scene[:team],
        project_id: foreign_project.id, kind: 'material', name: 'X', qty: '1'
      )
    end
    assert_match(/不属于当前团队/, e.message)
  end

  # payload：apply.projects 供新建表单项目下拉（readable 同源口径）
  def test_apply_block_includes_readable_projects_for_form
    scene = build_scene!
    body = Scinote::ElnUi::ResCenterPayload.call(user: scene[:creator], team: scene[:team])

    refute_nil body[:apply][:projects], 'projects 键必须存在（表单下拉数据源）'
    assert_includes body[:apply][:projects].map { |p| p[:id] }, scene[:project].id,
                    'readable 项目必须出现在下拉列表'
  end


  # ⚠ 原生 User 有三项presence 校验：full_name / initials / password(≥8)。
  #   早前这里只给 email+password:'x'，6 个用例全炸 RecordInvalid。
  def make_workflow_user!
    User.create!(
      email: "wf-#{SecureRandom.hex(4)}@x",
      password: 'password123',
      full_name: 'WF User',
      initials: 'WF'
    )
  end

  # ============================================================
  # 工厂（eln_ui 测试私有不进 access_control 工厂）
  # ============================================================

  private

  def scene_user
    # 同make_workflow_user!：原生User 要 full_name / initials / password≥8
    User.first || User.create!(
      email: "t-#{SecureRandom.hex(4)}@x",
      password: 'password123',
      full_name: 'Scene User',
      initials: 'SU'
    )
  end

  def scene_team
    Team.first || Team.create!(name: 't', created_by: scene_user)
  end

  def make_resource_application!(project:, requestor:, no: nil, status: 'draft')
    Scinote::ElnUi::ResourceApplication.create!(
      project: project,
      requestor: requestor,
      no: no || "SQ-2026-#{SecureRandom.hex(4).upcase}",
      status: status,
      items: [{ kind: 'material', name: 'PP 基料 K8003', qty: 20, unit: 'kg', unit_price: 350.0 }]
    )
  end

  # ⚠ 签名必须兼容基类 AcTest::Base#make_project!(team:, creator:, visibility:, strategy:)：
  #   这个类里的 build_scene! 走的是基类代码，调本类的覆盖版时**不传 name**。
  #   之前写死 `name:` 必填 → build_scene! 一进来就 ArgumentError（17 例全炸）。
  #   name 缺省时随机生成（与基类同款），要断言名字的用例自己显式传。
  def make_project!(team:, creator:, name: nil, visibility: :hidden, strategy: nil)
    Project.create!(
      team: team, name: name || "AC project #{SecureRandom.hex(4)}", created_by: creator,
      last_modified_by: creator, visibility: visibility, template: false
    ).tap { |p| p.experiment_visibility_strategy = strategy if strategy && p.respond_to?(:experiment_visibility_strategy=) }
  end
end
