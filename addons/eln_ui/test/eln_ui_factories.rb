# frozen_string_literal: true

# eln_ui 共享工厂：库存 / 流水 / 任务消耗造数
#
# 从 eln_ui_res_center_test.rb 抽出（2026-10-04 花费真源切换）：ResCenter 与
# 项目详情两处测试都要造「任务消耗行」，工厂逻辑 delicate（create_with_value!
# 混合 key、EAV 反查、polymorphic reference 等），复制两份必然漂移 —— 收到这里。
# 前置：AcTest::Base 的 make_project!/make_experiment!/make_task! 已就位
# （test_helper.rb require access_control 的 test_helper）。
module ElnUiFactories
  # 原生 Repository 不是光 create! 就行：库存值校验要求
  #   repository cell / repository column 必须存在、cell 必须在 column 列表里、
  #   cell 的 value type 必须与 column.data_type 一致。
  # 所以按原生结构建：column(data_type=RepositoryStockValue) → cell → stock_value
  # → unit item 挂到同一个 column 上。单位绝不塞给 SV（SV 没有 unit 列）。
  def make_active_repository!(team:, creator:, name: '测试库存', template: nil)
    repo = Repository.create!(
      team: team, name: name, created_by: creator,
      type: 'Repository', repository_template_id: template&.id
    )
    # repository_columns 表只有 created_by_id（没有 last_modified_by_id）
    column = RepositoryColumn.create!(
      repository_id: repo.id, name: '库存量', data_type: :RepositoryStockValue,
      created_by_id: creator&.id
    )
    repo.update!(selected_column_ids: [column.id]) if repo.respond_to?(:selected_column_ids=)
    repo.instance_variable_set(:@default_stock_column, column)
    define_singleton_method(:default_stock_column) { column }
    repo
  end

  def make_repository_row!(repository:, name: '测试材料', unit_price: 0,
                           amount: 0, unit: '—', creator:)
    row = RepositoryRow.create!(
      repository: repository, name: name, created_by: creator,
      last_modified_by: creator, unit_price: unit_price
    )
    column = repository_columns_of(repository).find { |c| c.data_type == 'RepositoryStockValue' }
    # ⚠ 两个必须照抄原生的细节，否则测试红而生产不红（或反之）：
    #   ① 必须用 RepositoryCell.create_with_value!，它按 column.data_type constantize
    #      出 RepositoryStockValue.new_with_payload。手写 RepositoryCell.create!(value: 数字)
    #      会让 polymorphic value_type 存成 "Integer" → 之后任何 inverse 解析都 NoMethodError。
    #   ② payload 是 **hash**（RepositoryStockValue#new_with_payload 读 payload[:amount]
    #      与 payload['unit_item_id']），传裸数字直接 TypeError: no implicit conversion of Symbol。
    #   ③ unit_item 得先建好再传 id进去 —— 原生也是这么串的。
    unit_item = unit.present? && column ? RepositoryStockUnitItem.create!(
      data: unit, repository_column_id: column.id,
      created_by_id: creator&.id, last_modified_by_id: creator&.id
    ) : nil
    RepositoryCell.create_with_value!(
      row, column,
      { amount: amount, low_stock_threshold: nil, 'unit_item_id' => unit_item&.id },
      creator
    )
    row # 调用方要的是 row（用 row.id / row.unit_price）
  end

  def repository_columns_of(repository)
    @_repo_columns ||= {}
    @_repo_columns[repository.id] ||= RepositoryColumn.where(repository_id: repository.id).to_a
  end

  # ⚠ 照抄原生 RepositoryStockValue#after_create 的建法：
  #   · 从 stock_value 侧 repository_ledger_records.create!（才有 repository_id）
  #   · reference 是**真 polymorphic**，原生指向 repository（不是 stock_value）——
  #     传 stock_value 会触发 inverse_of 解析 → "_reflect_on_association for Integer"
  #   · unit 由原生从 repository_stock_unit_item.data 自动拷，不手填
  # ⚠ repository_ledger_records 表**没有** last_modified_by_id 列（别照抄
  #   RepositoryStockValue / RepositoryRow）；原生 deduct_stock_balance 里那句
  #   stock_value.last_modified_by_id = ... 才是给它赋值的。
  def make_ledger_record!(repository:, stock_value:, amount: 0, balance: 0,
                          unit: nil, user: nil, unit_price: 0)
    rec = stock_value.repository_ledger_records.create!(
      amount: amount,
      balance: balance,
      reference: repository,
      user: user,
      my_module_references: { project_id: nil, experiment_id: nil, my_module_id: nil, team_id: nil },
      unit_price: unit_price
    )
    # 用例显式给了 unit 就以用例为准（原生自动拷的是 unit_item.data）
    rec.update_column(:unit, unit) if unit.present? && rec.unit != unit
    rec
  end

  # build_scene! 只给 team/creator/project；消耗链要的是「任务消耗」，
  # 所以在这条链上补一个实验 + 任务（都用基类 helper，last_modified_by 它们自己带）。
  def build_task_for(scene)
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    make_task!(experiment: exp, creator: scene[:creator])
  end

  # ⚠ MMR 的 around_save(:deduct_stock_balance) 会用 last_modified_by_id 去建
  #   RepositoryLedgerRecord（原生 deduct_stock_balance: user_id: last_modified_by_id || assigned_by_id），
  #   不给就会撞「Last modified by must exist」。
  #   单位同理照抄原生 consume_stock：从 repository_row 的库存值继承 unit_item，
  #   传 nil 的话 ledger.unit 为空 → 消耗行渲染成「20.0 —」。
  #   2026-10-04 起 MMR 消耗链路上挂了 eln_ui 的快照单价 decorator ——
  #   流水行 unit_price 会自动补 RepositoryRow.unit_price。
  def make_my_module_repository_row!(my_module:, repository_row:, assigned_by:, amount: 0, unit: nil)
    sv = RepositoryStockValue.joins(:repository_cell)
                             .where(repository_cells: { repository_row_id: repository_row.id }).first
    mmr = MyModuleRepositoryRow.create!(
      my_module: my_module,
      repository_row: repository_row,
      assigned_by: assigned_by,
      last_modified_by_id: assigned_by&.id,
      stock_consumption: amount,
      repository_stock_unit_item_id: sv&.repository_stock_unit_item_id
    )
    mmr
  end

  # 消耗/执行明细行（eln_ui_consume_records · REQ-RES-CONSUME）
  #
  # 两条来源路径（spec V1.21）：
  #   物资行 —— 由 MMR 消耗链路的 decorator 自动同步登记（L106，与 Ledger 一一对应）；
  #   服务行 —— 执行完成直接登记（L107，不写 Ledger；现阶段源 = 已完成的申请单 service
  #            项，见 _db/seed_consume_records.rb）。服务类测试直接走这个工厂造。
  #
  # ⚠ 唯一索引 (source_type, source_id)：同 (source) 重复造会 PG::UniqueViolation，
  #   需要多条服务行的用例请给不同 source_id（工厂源码由调用方传）。
  # ⚠ result_status 默认 settled（spec L109：验收通过才计入花费）；
  #   要验「待验收不计花费」传 result_status: 'pending_acceptance'。
  def make_consume_record!(project:, user: nil, kind: 'material', name: '测试项',
                           quantity: 1, unit: '次', unit_price: 0, amount: nil,
                           result_status: 'settled', source_type: 'TestSource', source_id: nil,
                           occurred_at: nil)
    Scinote::ElnUi::ConsumeRecord.create!(
      project: project,
      user: user,
      kind: kind,
      name: name,
      quantity: quantity,
      unit: unit,
      unit_price: unit_price,
      amount: (amount.nil? ? (quantity.to_d * unit_price.to_d) : amount),
      result_status: kind == 'service' ? result_status : nil,
      source_type: source_type,
      source_id: source_id || SecureRandom.number(1_000_000),
      occurred_at: occurred_at || Time.current
    )
  end
end
