# frozen_string_literal: true

# ELN UI —— 报告 §5 第 4 项：Ledger 冲正/失效（#5）+ 设备模板不产明细行（#6）
#
# #5 spec L901「当 该 Ledger 行被冲正或撤销，则 对应明细表行必须同步失效或冲正，
#     不得残留计入花费。」
#     🔴 这里有**两条**完全不同的路径，本文件都钉住：
#       ① 冲正 = 负 delta 的**新** Ledger 行（改消耗量/还回）
#          → 明细行天然被登记成负金额，对冲后花费归零；
#       ② 撤销 = Ledger 行**被销毁**（`repository_stock_value.rb:14` 的
#          `dependent: :destroy`）→ 明细行是addon 自有表，**不会跟着删**，
#          于是变成继续计花费的孤儿行 ← 这才是真缺口，本项修它。
#
# #6 spec L920「当 条目属于设备模板库存，则 其任务指派与预约**不产生**物资消耗行」——
#     早先只在**读侧**剔（res_center_payload 的 cost/consume block），
#     设备消耗行仍然躺在明细表里。规格要的是「不产生」，故判定收口到写侧。
require_relative 'test_helper'

class ElnUiLedgerSyncTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  def setup
    @scene = build_scene!
    @team  = @scene[:team]
  end

  def make_equipment_repo!(team:, creator:, name: '设备库')
    tmpl = ::RepositoryTemplate.create!(name: ::RepositoryTemplate.equipment.name, team: team)
    make_active_repository!(team: team, creator: creator, name: name, template: tmpl)
  end

  def latest_ledger
    RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow').order(id: :desc).take
  end

  def material_rows(source_id)
    Scinote::ElnUi::ConsumeRecord.where(source_type: 'RepositoryLedgerRecord', source_id: source_id)
  end

  # ============================================================
  # #6 设备模板库存不产生明细行
  # ============================================================

  def test_equipment_template_produces_no_material_row
    repo = make_equipment_repo!(team: @team, creator: @scene[:creator])
    row = make_repository_row!(repository: repo, name: '扫描仪机时', unit_price: 500.0,
                               amount: 100, unit: '次', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row,
                                   assigned_by: @scene[:creator], amount: 2)

    ledger = latest_ledger
    refute_nil ledger, '前提：原生消耗链路确实写了流水行'

    assert_equal 0, material_rows(ledger.id).count,
                 'SCN-RES-CONSUME-5：设备模板库存**不产生**明细行（写侧就不建，不是读侧剔）'
  end

  # ⚠ 读侧判定不能因为写侧收口就坏掉 —— 历史数据里设备行已经存在（写侧收口之前登记的），
  #   读侧仍必须剔掉它们，否则老数据的花费会虚高。
  #   模拟方式：直接改已有明细行指向**非设备**流水行，绕过唯一索引，
  #   再验读侧只剔「设备库」的行（与「明细表里有没有这行」无关）。
  def test_read_side_still_excludes_equipment_template_rows
    normal_repo = make_active_repository!(team: @team, creator: @scene[:creator], name: '普通原料库')
    normal_row = make_repository_row!(repository: normal_repo, name: 'POE 8150', unit_price: 420.0,
                                      amount: 100, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: normal_row,
                                   assigned_by: @scene[:creator], amount: 2)
    equipment_repo = make_equipment_repo!(team: @team, creator: @scene[:creator])
    equipment_row = make_repository_row!(repository: equipment_repo, name: '扫描仪机时',
                                         unit_price: 500.0, amount: 100, unit: '次',
                                         creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: equipment_row,
                                   assigned_by: @scene[:creator], amount: 2)

    normal_ledger = RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow')
                                          .order(id: :asc).first
    equipment_ledger = RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow')
                                             .order(id: :desc).first
    # 模拟「写侧收口之前」的历史数据：给设备流水行硬塞一条明细行。
    # ⚠ 必须给 source_id：save!(validate: false) 只跳模型校验，**不跳数据库 NOT NULL**。
    Scinote::ElnUi::ConsumeRecord.new(
      project: @scene[:project], kind: 'material', name: '历史设备行',
      quantity: 2, unit: '次', unit_price: 500.0, amount: 1000.0,
      occurred_at: Time.current, source_type: 'RepositoryLedgerRecord',
      source_id: equipment_ledger.id
    ).save!(validate: false) # 唯一索引会拦，测试里绕过（模拟存量脏数据）

    total = Scinote::ElnUi::ResCenterPayload.call(user: @scene[:creator], team: @team)[:cost]
    assert_equal '¥840', total[:reconciliation][:detailMaterialTotal],
                 '只有普通物资（2×420）计入；设备那1000 必须被读侧剔掉'
    assert_equal 1, total[:reconciliation][:detailMaterialRows]
    refute_nil normal_ledger
  end

  # 普通物资行**不能**被写侧收口误伤（fail-closed 方向反了就是全表拒）
  def test_normal_material_row_still_produced
    repo = make_active_repository!(team: @team, creator: @scene[:creator], name: '普通原料库')
    row = make_repository_row!(repository: repo, name: 'POE 8150', unit_price: 420.0,
                               amount: 100, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row,
                                   assigned_by: @scene[:creator], amount: 5)

    ledger = latest_ledger
    refute_nil ledger
    rec = material_rows(ledger.id).first

    refute_nil rec, '普通物资必须照常登记明细行'
    assert_equal 'material', rec.kind
    assert_equal 2100.0, rec.amount.to_f, '5 × 420'
  end

  # ⚠ 「设备模板存在但库存不属于它」≠「查不出设备模板」：
  #   判定必须按**库存↔模板归属**（spec L920 强制），而不是「有没有设备模板」这个全局事实。
  #   库里恒有 bootstrap 的设备模板行，所以真正要守的是：
  #   存在设备模板时，**非设备库**的普通物资照常登记（不能被 fail-closed 误伤）。
  def test_non_equipment_repo_registers_even_when_equipment_template_exists
    assert_equal true, Scinote::ElnUi::EquipmentTemplateFilter.rule_active?,
                 '前提：设备模板规则可判'
    make_equipment_repo!(team: @team, creator: @scene[:creator]) # 团队确实有设备库

    repo = make_active_repository!(team: @team, creator: @scene[:creator], name: '无模板库')
    row = make_repository_row!(repository: repo, name: '滑石粉', unit_price: 100.0,
                               amount: 50, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row,
                                   assigned_by: @scene[:creator], amount: 2)

    ledger = latest_ledger
    refute_nil material_rows(ledger.id).first,
             '非设备库的物资必须照常登记（判定看归属，不看「团队有没有设备」）'
  end

  # 团队**一个设备模板都没建**时，也必须照常登记（这是「两种空」里被压错的那一种）
  def test_team_without_any_equipment_repo_still_registers
    repo = make_active_repository!(team: @team, creator: @scene[:creator], name: '干净库')
    row = make_repository_row!(repository: repo, name: '滑石粉', unit_price: 100.0,
                               amount: 50, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row,
                                   assigned_by: @scene[:creator], amount: 2)

    ledger = latest_ledger
    refute_nil material_rows(ledger.id).first, '没有哪条属于设备 → 全部正常登记（不能一律拒）'
  end

  def test_equipment_filter_predicate_direction
    assert_equal true, Scinote::ElnUi::EquipmentTemplateFilter.rule_active?,
                 'equipment 模板是内置的，probe 恒可得'
    assert_equal false, Scinote::ElnUi::EquipmentTemplateFilter.equipment_row?(nil)
    assert_equal false, Scinote::ElnUi::EquipmentTemplateFilter.equipment_row?(0)
  end

  # ============================================================
  # #5-① 冲正：负 delta 新行 → 明细行对冲
  # ============================================================

  def test_negative_ledger_row_creates_negative_material_row
    repo = make_active_repository!(team: @team, creator: @scene[:creator])
    row = make_repository_row!(repository: repo, name: 'POE 8150', unit_price: 100.0,
                               amount: 100, unit: 'kg', creator: @scene[:creator])
    task = build_task_for(@scene)
    mmr = make_my_module_repository_row!(my_module: task, repository_row: row,
                                         assigned_by: @scene[:creator], amount: 10)
    positive = material_rows(latest_ledger.id).first
    assert_equal 1000.0, positive.amount.to_f

    # 还回 3 件 → 原生写一条**负** delta 的流水行
    mmr.update!(stock_consumption: 7)
    negative_ledger = latest_ledger
    refute_equal positive.source_id, negative_ledger.id, '还回必须产生新流水行'
    assert_equal(-3.0, negative_ledger.amount.to_f)

    negative = material_rows(negative_ledger.id).first
    refute_nil negative, '还回也必须登记明细行'
    assert_equal(-300.0, negative.amount.to_f, '明细行金额必须带负号')
    assert_equal 700.0, positive.amount.to_f + negative.amount.to_f,
                 '冲正后净花费 = 700（不是 1300 —— 取绝对值的老 bug）'
  end

  # ============================================================
  # #5-② 撤销：Ledger 行被销毁 → 明细行同步作废（这是本项修的真缺口）
  # ============================================================

  def test_destroying_stock_value_invalidates_material_row
    repo = make_active_repository!(team: @team, creator: @scene[:creator])
    row = make_repository_row!(repository: repo, name: 'POE 8150', unit_price: 100.0,
                               amount: 100, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row,
                                   assigned_by: @scene[:creator], amount: 10)

    ledger = latest_ledger
    rec = material_rows(ledger.id).first
    refute_nil rec
    assert_equal 1000.0, rec.amount.to_f, '前提：先记上一笔 ¥1000'

    # 删库存条目 → 原生 dependent: :destroy 会带走 Ledger 行
    stock_value = RepositoryStockValue.joins(:repository_cell)
                                     .where(repository_cells: { repository_row_id: row.id }).first
    refute_nil stock_value
    stock_value.destroy!

    rec.reload
    assert_equal 0, rec.amount.to_f,
                 'SCN-RES-CONSUME-1：来源 Ledger 行消失后，明细行必须同步失效，不得残留计花费'
    assert_includes rec.name, '已作废', '作废要留痕（花费是审计凭据，不能物理删除）'
  end

  # 直接调作废入口（不经 destroy）也要对：回填脚本会走这条路径
  def test_invalidate_material_rows_entry_point
    repo = make_active_repository!(team: @team, creator: @scene[:creator])
    row = make_repository_row!(repository: repo, name: 'POE 8150', unit_price: 100.0,
                               amount: 100, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row,
                                   assigned_by: @scene[:creator], amount: 10)

    stock_value = RepositoryStockValue.joins(:repository_cell)
                                     .where(repository_cells: { repository_row_id: row.id }).first
    count = Scinote::ElnUi::ConsumeRecord.invalidate_material_rows_for_stock_value!(stock_value)

    assert_equal 1, count, '应作废恰好一行'
    assert_equal 0, Scinote::ElnUi::ConsumeRecord.where(source_type: 'RepositoryLedgerRecord')
                                                .where.not(amount: 0).count,
                 '作废后不得还有非零的该来源明细行'
  end

  # 幂等：作废两次不能报错、也不能把 already-zero 的行算进count
  def test_invalidate_is_idempotent
    repo = make_active_repository!(team: @team, creator: @scene[:creator])
    row = make_repository_row!(repository: repo, name: 'POE 8150', unit_price: 100.0,
                               amount: 100, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row,
                                   assigned_by: @scene[:creator], amount: 10)

    stock_value = RepositoryStockValue.joins(:repository_cell)
                                     .where(repository_cells: { repository_row_id: row.id }).first
    assert_equal 1, Scinote::ElnUi::ConsumeRecord.invalidate_material_rows_for_stock_value!(stock_value)
    assert_equal 0, Scinote::ElnUi::ConsumeRecord.invalidate_material_rows_for_stock_value!(stock_value),
                 '第二次没有非零行可作废'
  end

  # 作废不能波及**服务行**（source_type 不同）与别的库存的物料行
  def test_invalidate_does_not_touch_service_or_other_rows
    repo_a = make_active_repository!(team: @team, creator: @scene[:creator], name: '库A')
    row_a = make_repository_row!(repository: repo_a, name: '甲材料', unit_price: 100.0,
                                 amount: 50, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row_a,
                                   assigned_by: @scene[:creator], amount: 2)
    repo_b = make_active_repository!(team: @team, creator: @scene[:creator], name: '库B')
    row_b = make_repository_row!(repository: repo_b, name: '乙材料', unit_price: 200.0,
                                 amount: 50, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row_b,
                                   assigned_by: @scene[:creator], amount: 3)

    service = make_consume_record!(project: @scene[:project], user: @scene[:creator],
                                   kind: 'service', name: 'DSC', quantity: 1, unit: '次',
                                   unit_price: 1200, source_type: 'TestSource', source_id: 987_654)
    kept_material = material_rows(latest_ledger.id).first
    refute_nil kept_material

    stock_value_a = RepositoryStockValue.joins(:repository_cell)
                                      .where(repository_cells: { repository_row_id: row_a.id }).first
    Scinote::ElnUi::ConsumeRecord.invalidate_material_rows_for_stock_value!(stock_value_a)

    assert_equal 1200.0, service.reload.amount.to_f, '服务行不受影响（1 次 × ¥1200）'
    assert_equal 600.0, kept_material.reload.amount.to_f, '别的库存的物料行不受影响（3 × ¥200）'
  end

  # ============================================================
  # 回归护栏：收口后花费页签与对账仍自洽
  # ============================================================

  def test_cost_block_still_consistent_after_changes
    repo = make_active_repository!(team: @team, creator: @scene[:creator])
    row = make_repository_row!(repository: repo, name: 'POE 8150', unit_price: 100.0,
                               amount: 100, unit: 'kg', creator: @scene[:creator])
    make_my_module_repository_row!(my_module: build_task_for(@scene), repository_row: row,
                                   assigned_by: @scene[:creator], amount: 10)

    body = Scinote::ElnUi::ResCenterPayload.call(user: @scene[:creator], team: @team)
    recon = body[:cost][:reconciliation]

    assert_equal true, recon[:equipmentRuleActive]
    assert_equal 1, recon[:detailMaterialRows]
    assert_equal '¥1,000', recon[:detailMaterialTotal]
    assert_equal true, recon[:consistent], '明细 ↔ Ledger 一一对应，对账闸门必须仍通过'
  end
end
