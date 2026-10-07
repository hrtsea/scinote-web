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

  # 测试表征服务档案条目（eln_ui_service_catalogs · REQ-RES-ARCHIVE / REQ-RES-TEST）
  #
  # 服务行的单价与「是否需验收」都取自这里 —— 建档时就要把这两件事定死，
  # 登记服务行时不得另找来源（spec V1.21 L986：档案是服务目录的唯一载体）。
  def make_service_catalog!(name: 'DSC 差示扫描量热', unit_price: 1200,
                            requires_acceptance: true, cycle_days: nil, vendor: nil)
    Scinote::ElnUi::ServiceCatalog.create!(
      name: name,
      unit_price: unit_price,
      requires_acceptance: requires_acceptance,
      cycle_days: cycle_days,
      vendor: vendor
    )
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

  # 材料类申请的「目标库」—— ADR-0030 D7 起**必填**（申请时就要选定这批料进哪个库）。
  #
  # 绝大多数用例只关心「单子能不能建 / 审批流转 / 花费归集」，并不关心料进哪个库；
  # 让十几处调用点各建一个库既啰嗦又会漂移。统一给一个本团队、**带库存列**的库
  # （make_active_repository! 会一并建好 RepositoryStockValue 列 —— 入库写侧要用它）。
  #
  # ⚠ 关心「进了哪个库 / 库内条目与 Stock 怎么变」的用例，自己传 repository_id 覆盖，
  #   **不要**改这个默认值 —— 改了会让「目标库校验」的护栏用例失去意义。
  # ⚠ 实例级 memo（与 @_repo_columns 同款）：minitest 每个用例一个新实例，
  #   不会跨用例复用；写成类级 memo 才会串味（见 dev-pitfalls）。
  def target_repository(team:, creator:)
    @_target_repository ||= make_active_repository!(
      team: team, creator: creator, name: '默认目标库'
    )
  end

  def target_repository_id(team:, creator:)
    target_repository(team: team, creator: creator).id
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
  # 把某个用户提为**项目负责人**（REQ-TASK-CLOSE 的唯一审核人）
  #
  # ⚠ 为什么必须 find_or_initialize_by + update!，不能 create!：
  #   UserAssignment 有 `validates :user, uniqueness: { scope: %i[assignable team_id] }`，
  #   build_scene! / InheritUserAssignmentsJob 很可能已经给同一 (user, project, team)
  #   落过一行（组员角色），再造一行直接 RecordInvalid。
  #   「升角色」是宿主既有语义 —— 原生也是靠 upsert 改 user_role_id 完成的。
  def make_project_owner!(project, user:, team: nil)
    team ||= project.team
    ua = UserAssignment.find_or_initialize_by(user: user, assignable: project, team_id: team&.id)
    ua.user_role = UserRole.find_predefined_owner_role
    ua.assigned = :manually
    ua.save!
    ua
  end

  # 任务关闭申请单（eln_ui_task_close_requests · REQ-TASK-CLOSE）
  #
  # ⚠ 直接建行，不走 TaskCloseWorkflow —— 这些用例要的是「已经处于某审核态」的前置，
  #   走 workflow 就变成在测被测对象了。status 三档与 spec SCN-TASK-CLOSE-1/3/4 一一对应。
  def make_task_close_request!(my_module:, submitted_by:, status: 'pending',
                               reviewer: nil, reason: nil, submitted_at: nil)
    Scinote::ElnUi::TaskCloseRequest.create!(
      my_module: my_module,
      status: status,
      submitted_by: submitted_by,
      submitted_at: submitted_at || Time.current,
      reviewer: reviewer,
      reviewed_at: %w[approved rejected].include?(status) ? Time.current : nil,
      reason: reason
    )
  end

  # REQ-RES-APPROVER：把 user 配成该项目的审批人（默认两阶段都配）。
  # ⚠ 闸门已 fail-closed —— 不配就没人能批。这是测试里「造一个合法审批人」的**唯一入口**：
  #   别在用例里直接 ProjectApprover.add!，否则将来加列要改十几处，且每处都可能漏。
  # ⚠ 反过来也别把这段塞进 build_scene! 自动给所有人配上 —— 那会让「未配置 → 卡住」
  #   的护栏用例永远绿（绿在养 bug）。谁要审批，谁显式配。
  def configure_approver!(user:, project:, stages: Scinote::ElnUi::ProjectApprover.stages)
    stages.each do |stage|
      Scinote::ElnUi::ProjectApprover.add!(project: project, user: user, stage: stage)
    end
    true
  end

  # 清空某项目的审批名单 —— fail-closed 护栏用例用它把场景还原到「没人配」
  def clear_approvers!(project)
    Scinote::ElnUi::ProjectApprover.for_project(project).delete_all
  end

  # REQ-RES-RECEIPT：造一条「待验」验收记录（带假到货照片）。
  #
  # ⚠ 为什么**直接建记录**而不走 `submit_receipt` 动作：多数用例要验的是**验货之后**的行为
  #   （入库、落库条目回写、任务消耗溯源、花费），前置只需要「有一条待验记录」这个状态。
  #   动作本身的规则（照片必传 / 数量必填 / 重复提交拦截 / 只有本人能交）
  #   由 eln_ui_receipt_verification_test.rb 专门守，两边不重复。
  #
  # ⚠ 照片用 StringIO 假件：test 环境 `config.active_storage.service = :test`，
  #   不需要真的图片字节，也不需要清理磁盘。
  # ⚠ `configure_approver!` 的默认 stages 取自 `ProjectApprover.stages`（已含 receipt），
  #   所以「造一个能验货的人」不需要额外调用 —— 但下面仍显式写一次 stage，
  #   免得将来有人改默认值时这些用例集体变红却看不出原因。
  def make_pending_receipt!(app:, qty: nil, photos: 1, created_by: nil)
    v = Scinote::ElnUi::ReceiptVerification.create!(
      resource_application: app, status: 'pending',
      qty: qty || Scinote::ElnUi::ReceiptVerification.applied_qty(app),
      created_by: created_by || app.requestor
    )
    photos.to_i.times do |i|
      v.photos.attach(
        io: StringIO.new("fake-jpeg-#{i}"),
        filename: "receipt-#{i}.jpg", content_type: 'image/jpeg'
      )
    end
    v
  end

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
