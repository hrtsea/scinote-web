# frozen_string_literal: true
#
# ELN UI —— 项目详情页数据装配（Scinote::ElnUi::ProjectDetailPayload）
#
# 这条测试守的是「改造」最容易翻车的一点：**把真数据映射成原型字段时顺手编数**。
# 所以每条断言都同时盯两件事：
#   1. 值确实来自真库（name / id / created_at / UA 角色 / MyModule 计数）；
#   2. 原生没有的字段（项目编号、项目来源）走的是「显式留白」而不是造一个漂亮的值。

require_relative 'test_helper'

class ElnUiProjectDetailTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories # 库存/流水/任务消耗工厂（eln_ui_factories.rb，与 ResCenter 测试共享）

  def test_project_basic_maps_real_columns
    scene = build_scene!
    project = scene[:project]

    basic = payload(scene)[:projectBasic]

    assert_equal project.name, basic[:name], '项目名称必须来自 projects.name'
    assert_equal "##{project.id}", basic[:code], '编号用主键（原生无项目编号列）'
    assert_equal project.created_at.strftime('%Y-%m-%d'), basic[:foundedAt], '立项时间取 created_at'
    assert_equal '执行中', basic[:status], '未归档项目应为「执行中」'
    assert_nil basic[:source], '原生无「项目来源」字段 —— 必须留白，不许编'
    assert_equal project.description.to_s.strip, basic[:description]
  end

  # 真机最容易漏的一条：projects.description 存的是**后台富文本 HTML**，
  # 原型按文本渲染（ProjectDetail.vue {{ pb.description }}）—— 不剥标签，
  # 生产页上会直接吐出 <div class="sci-checkbox-container">… 源码。
  # 这条守「剥了、但没把内容弄丢」这个中间地带。
  def test_description_is_stripped_of_markup_but_keeps_text
    scene = build_scene!
    project = scene[:project]
    project.update!(description: '<div class="sci-checkbox-container">Grant access to all</div>')

    basic = payload(scene)[:projectBasic]

    refute_includes basic[:description], '<div', 'HTML 标签不能出现在页面上'
    assert_includes basic[:description], 'Grant access to all', '文字内容必须保留'
  end

  def test_members_carry_real_user_and_role
    scene = build_scene!
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :normal)

    row = payload(scene)[:members].find { |m| m[:name] == member.full_name }

    refute_nil row, '真实成员必须出现在成员表里'
    # ⚠ 宿主预定义角色真名是 **'User'**（不是原型的 'Normal user'），别照抄原型文案
    assert_equal 'User', row[:role], 'UserRole 名必须原样透出'
    assert_equal '小组组长', row[:title], 'User → 原型业务称谓「小组组长」'
    assert_equal member.created_at.strftime('%Y-%m-%d'), row[:joined], '加入时间取 UA created_at'
    assert_includes %w[blue green orange cyan purple], row[:color]
  end

  def test_experiments_map_real_rows_and_counts
    scene = build_scene!
    project = scene[:project]
    exp = make_experiment!(project: project, creator: scene[:creator])
    make_task!(experiment: exp, creator: scene[:creator])

    row = payload(scene)[:experiments].first

    refute_nil row
    assert_equal 1, payload(scene)[:experiments].size, '真库里就这一个实验'
    assert_equal "#{exp.id} · #{exp.name}", row[:fullName], '行名 = 主键 · 名称'
    assert_includes %w[active notstarted done], row[:status], '状态必须是原型的三态之一'
    assert_equal({ done: 0, total: 1 }, row[:progress], '任务数按 MyModule 真实计数')
    assert_equal "/projects/#{project.id}/experiments/#{exp.id}", row[:href], '链接指回宿主真实路由'
    refute_nil row[:owner][:name], '实验负责人取 created_by'
    # ⚠ 别写成 assert_nil(x.nil?) —— 那是断言布尔值，写反了永远看不出配色漏了
    refute_nil row[:owner][:color], '头像配色必须落在原型调色板内'
    assert_includes %w[blue green orange cyan purple], row[:owner][:color]
  end

  def test_owner_resolves_from_real_user
    scene = build_scene!
    creator = scene[:creator]

    owner = payload(scene)[:projectBasic][:owner]

    assert_includes owner, creator.full_name, '负责人取 supervised_by / created_by 的真名'
  end

  # 视图侧的挂载契约：任何一边改名，这条会立刻红（bundle 找不到节点会静默不渲染）
  def test_project_detail_page_mounts_vue_bundle
    scene = build_scene!
    make_experiment!(project: scene[:project], creator: scene[:creator])

    html = open_detail(scene[:creator], scene[:project])

    assert_includes html, 'id="eln-project-detail"', '挂载点必须存在'
    assert_includes html, 'id="eln-project-detail-data"', '数据注入块必须存在'
    assert_includes html, 'eln_project_detail', 'Vue bundle 必须被引入'
    assert_includes html, 'eln-system-vue3', '原型样式表必须被引入'
    assert_includes html, scene[:project].name, '页面必须带真项目名（走宿主 layout）'
  end

  # ------------------------------------------------------------
  # 「下钻数据」契约（用户 2026-10-04 报：详情页里还是原型演示值）
  #
  # 原生 SciNote 没有项目级指标 / 项目文档台账 / 花费模型，payload 必须**显式给空集**，
  # 让前端注入时把原型的画布演示值（指标 3 条、必传文档 5 类、花费 ¥86.4万）
  # 无条件替换掉 —— 空集落到组件走「空态」，而不是拿演示值顶。
  # ⚠ 这里最阴的是「不返回这个键」：前端注入时 `injected.projectCost || {}`
  #   看着有兜底，其实**留着就是原型值**。所以必须断言「键存在且为空」，
  #   而不是「键不存在也不报错」。
  # ------------------------------------------------------------
  def test_drilldown_only_sections_are_explicitly_empty
    scene = build_scene!
    body = payload(scene)

    # 2026-10-04 起：指标/文档落自有表（eln_ui_project_metrics/documents），
    # 花费真源 = Ledger 任务消耗行（2026-10-04 二次切换，与资源中心同源）。
    # 「空」语义：无行/无消耗 → 显式空集，前端才不会 fallback 到原型演示值。
    assert_equal [], body[:projectMetrics], '无指标行 → 显式空数组（空态）'
    assert_equal [], body[:requiredDocs], '无必传文档行 → 显式空数组'
    assert_equal [], body[:otherDocs], '无其他文档行 → 显式空数组'

    cost = body[:projectCost]
    refute_nil cost, 'projectCost 必须存在（缺键 = 前端 fallback 到原型 ¥86.4万）'
    assert_equal [], cost[:rows], '无消耗行 → rows 空'
    assert_equal [], cost[:splits], '无消耗行 → splits 空'
    assert_nil cost[:total], '无消耗行 → total 为 nil（不许出现原型演示金额）'
  end

  # ------------------------------------------------------------
  # 2026-10-04 落地：三个自有表有行时，payload 必须逐字段映射成原型形状。
  # 同时守「汇总现算不落表」：total / share 由服务端算，改了表不许忘了算。
  # ------------------------------------------------------------
  def test_metrics_documents_cost_read_from_addon_tables
    scene = build_scene!
    project = scene[:project]
    creator = scene[:creator]

    Scinote::ElnUi::ProjectMetric.create!(project: project, name: '拉伸剪切强度',
                                          target: '≥ 8.0 MPa', current: '8.2 MPa', ok: true, position: 1)
    Scinote::ElnUi::ProjectMetric.create!(project: project, name: '保留率',
                                          target: '≥ 75%', current: '70%', ok: false, position: 2)
    Scinote::ElnUi::ProjectDocument.create!(project: project, name: '项目任务书',
                                            category: 'required', version: 'v2',
                                            uploaded: true, uploaded_on: Date.new(2026, 3, 2), position: 1)
    Scinote::ElnUi::ProjectDocument.create!(project: project, name: '结题报告',
                                            category: 'required', uploaded: false, position: 2)
    Scinote::ElnUi::ProjectDocument.create!(project: project, name: '对比测试报告.pdf',
                                            category: 'other', doc_type: '执行',
                                            uploader: creator, uploaded: true,
                                            uploaded_on: Date.new(2026, 9, 28), position: 3)
    # 花费：真源 = Ledger 任务消耗行（2026-10-04 切换，与资源中心花费页签同源）。
    # 造 20 × 350 = ¥7,000 的任务消耗（走原生 MMR 消耗链 + 快照单价 decorator）。
    repo = make_active_repository!(team: scene[:team], creator: creator)
    row = make_repository_row!(repository: repo, unit_price: 350.0, amount: 100,
                               unit: 'kg', creator: creator)
    make_my_module_repository_row!(my_module: build_task_for(scene), repository_row: row,
                                   assigned_by: creator, amount: 20)

    body = payload(scene)

    assert_equal 2, body[:projectMetrics].size
    m = body[:projectMetrics].first
    assert_equal({ name: '拉伸剪切强度', target: '≥ 8.0 MPa', current: '8.2 MPa', ok: true },
                 { name: m[:name], target: m[:target], current: m[:current], ok: m[:ok] },
                 '指标四字段逐一对齐原型 mock 形状')

    req = body[:requiredDocs]
    assert_equal 2, req.size
    assert_equal({ name: '项目任务书', ver: 'v2', date: '2026-03-02', uploaded: true }, req.first,
                 '必传文档映射 name/ver/date/uploaded')
    assert_equal({ name: '结题报告', ver: '—', date: '—', uploaded: false }, req.last,
                 '未上传文档显式留白（—），不编日期')

    other = body[:otherDocs].first
    assert_equal '执行', other[:type]
    assert_equal creator.full_name.presence.to_s, other[:by], '登记人取真用户全名'

    cost = body[:projectCost]
    assert_equal '¥7,000', cost[:total], '总额 = 20 × 350（明细表行 × 快照单价）'
    assert_equal 1, cost[:rows].size, '只有物资行（本例无服务明细行）'
    assert_equal '物资消耗', cost[:rows].first[:category]
    assert_equal '¥7,000', cost[:rows].first[:amount]
    assert_equal '100%', cost[:rows].first[:share], '占比现算'
    assert_equal({ key: 'project', label: '仅项目' }, cost[:scopes].first, 'scope 开关形状与原型一致')
    assert_includes cost[:note], 'SCN-RES-COST-1', '口径说明必须写明真来源，不许抄原型演示口径'
  end

  # ★ 项目花费的服务执行（OPEN-9 闭环 · spec L107~L109）：服务行走明细表、不写 Ledger，
  #   只有 settled（验收通过）才计入；与资源中心花费页签同口径（L108 唯一对外数据源）。
  def test_cost_includes_service_execution_rows
    scene = build_scene!
    project = scene[:project]
    creator = scene[:creator]

    make_consume_record!(project: project, user: creator, kind: 'service',
                         name: 'DSC 差示扫描量热', quantity: 2, unit: '次',
                         unit_price: 600, amount: 1_200, result_status: 'settled',
                         source_type: 'Scinote::ElnUi::ResourceApplication', source_id: 88_880_001)
    make_consume_record!(project: project, user: creator, kind: 'service',
                         name: '万能材料试验机（拉伸）', quantity: 3, unit: '次',
                         unit_price: 200, amount: 600, result_status: 'pending_acceptance',
                         source_type: 'Scinote::ElnUi::ResourceApplication', source_id: 88_880_002)

    cost = payload(scene)[:projectCost]

    assert_equal '¥1,200', cost[:total], '只计 settled 服务行（1,200），待验收的 600 不计'
    assert_equal 2, cost[:rows].size, '物资 + 服务两类行都出现'
    assert_equal '服务执行', cost[:rows].last[:category]
    assert_includes cost[:note], 'spec L109', '口径说明写明验收闸门语义'
  end

  # metricProgress：有真指标行时页头标签用「指标 x/y 达标」，不再退回实验完成度。
  def test_metric_progress_prefers_real_metrics
    scene = build_scene!
    project = scene[:project]
    Scinote::ElnUi::ProjectMetric.create!(project: project, name: '达标项',
                                          target: '≥ 1', current: '1', ok: true, position: 1)
    Scinote::ElnUi::ProjectMetric.create!(project: project, name: '未达标项',
                                          target: '≥ 2', current: '0', ok: false, position: 2)

    body = payload(scene)

    assert_equal '指标 1/2 达标', body[:projectBasic][:metricProgress]
  end

  # 与上一组配套：真有的那几块必须是真的 —— 实验条数、成员条数都对得上真库。
  def test_drilldown_real_sections_match_database
    scene = build_scene!
    project = scene[:project]
    2.times { |i| make_experiment!(project: project, creator: scene[:creator], name: "下钻实验#{i}") }

    body = payload(scene)

    assert_equal project.experiments.count, body[:experiments].size, '实验列表条数 = 真库条数'
    assert_equal project.user_assignments.where(assignable_type: 'Project').count,
                 body[:members].size, '成员条数 = 真库 UA 条数'
    body[:experiments].each do |e|
      assert_match(/^\d+ · /, e[:fullName], '实验行显示「主键 · 名称」，不编 EX1 这种业务编号')
    end
  end

  private

  def payload(scene)
    Scinote::ElnUi::ProjectDetailPayload.call(scene[:project])
  end

  def open_detail(user, project)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.get("/projects/#{project.id}/eln_project_detail")
    assert_includes [200], session.response.status, '负责人应能打开项目详情页'
    session.response.body
  end
end
