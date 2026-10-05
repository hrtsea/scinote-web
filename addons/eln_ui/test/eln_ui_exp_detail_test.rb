# frozen_string_literal: true
#
# ELN UI —— 实验详情页（PRD §7.7 PAGE-EXP-DETAIL）的数据装配与视图契约
#
# 与列表页那份同一条规矩：值必须来自真库，原生没有的字段走「显式留白/推导」，
# 不许为了好看编一个数。实验页额外守四件前两页不碰的事：
#   1. 状态是**映射**出来的（原生 MyModuleStatus 三档 → 原型 status 取值域三档）；
#   2. 「实验设计与配方优化」入口按**宿主权限**裁剪（DEC-001 组员不可见），
#      准入用原生 ExperimentPermissions::MANAGE 近似（近似映射已记 OPEN-4）；
#   3. 默认左栏页签是 tasks（PRD §7.7「tasks 默认选中」），且首屏是真任务表而不是
#      原型那块硬编码假文案；
#   4. 标题 / 面包屑项目名 / 状态徽标必须来自真库 —— 原型这三处是写死的演示文案。

require_relative 'test_helper'

class ElnUiExpDetailTest < AcTest::Base
  include Warden::Test::Helpers

  def test_task_rows_map_real_columns
    scene = build_scene!
    project = scene[:project]
    exp = make_experiment!(project: project, creator: scene[:creator])
    task = make_task!(experiment: exp, creator: scene[:creator])
    # 贴近真机：原生新建任务会落到默认状态流（Not started），测试工厂挂的任务
    # 默认没状态行 → status 是 nil。这里显式挂一行，避免把「工厂差异」当成 payload 缺陷。
    # ⚠ 不在这里给 payload 兜底：真机上真有没状态的任务（原生就没给），
    #   那就该显示空白，而不是偷偷补一个假状态。
    ensure_default_status_flow!
    status = MyModuleStatus.where(name: 'Not started').first
    task.update_columns(my_module_status_id: status.id)

    row = payload(exp, scene[:creator])[:tasks].first

    assert_equal task.id.to_s, row[:id], 'id 用主键字符串（原生无业务编号列）'
    assert_equal task.name, row[:name], '名称来自 my_modules.name'
    # 原型的 status 取值域就这五个，映射不进来的值不许硬塞（宁可前端显示不出中文）
    assert_includes %w[pending active submitted pendingReview closed], row[:status]
    assert_equal 'pending', row[:status], 'default 状态流里 Not started → pending'
    refute_nil row[:owner], '指派列必须存在（没人指派时是空头像，不是 nil 崩页面）'
    assert_equal task.due_date&.strftime('%Y-%m-%d'), row[:due], '截止日期格式化成 YYYY-MM-DD'
  end

  # 原生默认状态流三档 → 原型三档。映射错了前端就是「状态列空白」，
  # 这类错在单测里一眼看得见，真机上却容易被当成「页面还没做」。
  # ⚠ 用 update_columns 直接写列：MyModule#update! 会跑状态流转回调，
  #   把 status_changing 之类一起改掉，测的就不是我们想测的映射了。
  def test_status_maps_default_flow_to_prototype_domain
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    # ⚠ 顺序依赖加固：默认状态流是**在测试事务内**建的（ensure_default 只有 without bang），
    #   事务一回滚这三行就没了 —— 之前这条测试靠「排在建过流的那条之后」才绿，
    #   minitest 随机顺序一换就整条跳过。这里显式建，别把命脉挂在用例顺序上。
    ensure_default_status_flow!

    {
      'Not started' => 'pending',
      'In progress' => 'active',
      'Completed' => 'closed'
    }.each do |native, prototype|
      task = make_task!(experiment: exp, creator: scene[:creator])
      status = MyModuleStatus.where(name: native).first
      next puts("  · 跳过 #{native}（库里没有这行）") if status.blank?

      task.update_columns(my_module_status_id: status.id)
      row = payload(exp, scene[:creator])[:tasks].find { |t| t[:id] == task.id.to_s }

      assert_equal prototype, row[:status], "原生 #{native} 应映射到原型 #{prototype}"
    end
  end

  # 显式留白：原生没有 DOE 设计变量表 → 空数组，而不是隐身（面板照常渲染空表）。
  def test_design_vars_are_blank_not_invented
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])

    assert_equal [], payload(exp, scene[:creator])[:expDesignVars],
                   '原生无 DOE 变量 → 显式留白；不许编造设计变量'
  end

  # ------------------------------------------------------------
  # 二开自有表（eln_ui_*）—— 原生没有承载面的那几格全落在这两张表里。
  # 铁律：只往**自己的**表写，原生表（experiments / users / projects）一字不动。
  # ------------------------------------------------------------

  # 实验目的 / 实验方案与方法：原生**没有**「目的」「方法步骤」这两列，
  # 以前页面上顶着的是原型硬编码的演示文案（Dow ADH-6066 / 5 条假步骤）。
  def test_purpose_and_method_come_from_experiment_profile
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    Scinote::ElnUi::ExperimentProfile.create!(
      experiment: exp,
      business_code: 'ELN-EXP-2026-001',
      purpose: '筛选 150°C 蒸汽下耐高温硅胶的固化剂配比窗口。',
      method: "基材打磨除油\n底涂固化 150°C×30min"
    )

    data = payload(exp, scene[:creator])

    assert_equal '筛选 150°C 蒸汽下耐高温硅胶的固化剂配比窗口。', data[:expPurpose], '目的取实验档案'
    assert_equal "基材打磨除油\n底涂固化 150°C×30min", data[:expMethod], '方法取实验档案（多行原样给）'
    refute_includes data[:expPurpose], 'ADH-6066', '有档案时不许再渲染原型的演示文案'
  end

  # 没有档案时：目的回落到原生 description（原生**有**这一列，不算编造）。
  # ⚠ 原生存的是富文本 HTML，直接透传页面上会看到一整段 <div class="sci-…"> 源码，
  #   所以这里压成纯文本（与项目详情同源的处理）。
  def test_purpose_falls_back_to_native_description_sanitized
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    exp.update_columns(description: '<div class="sci-checkbox-container">压实后的目的文本</div>')

    assert_equal '压实后的目的文本', payload(exp, scene[:creator])[:expPurpose],
                 '无档案时目的回落到原生 description，且富文本已压成纯文本'
  end

  # 既没档案也没 description —— 必须显式留白（空串），不能把演示文案当真值。
  def test_purpose_and_method_blank_when_no_profile_and_no_description
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator], run_inherit: false)
    exp.update_columns(description: nil)

    data = Scinote::ElnUi::ExpDetailPayload.call(exp, scene[:creator], can_manage_experiment: true)

    assert_equal '', data[:expPurpose], '无档案无描述 → 留白，不许拿演示文案顶'
    assert_equal '', data[:expMethod], '无档案 → 方法留白'
    assert_equal [], data[:expDesignVars], '无变量行 → 空表'
  end

  # DOE 设计变量表（纯二开）：有数据就按结构化区间渲染，没有就是空表。
  def test_design_vars_come_from_addon_table_with_structural_range
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    # categorical（牌号）没有区间，range 必须留白而不是硬凑字符串
    Scinote::ElnUi::DesignVariable.create!(experiment: exp, name: 'POE 增韧剂', var_type: 'float',
                                           range_min: 5, range_max: 25, unit: '%',
                                           constraint: '优先取水平中心', position: 0)
    Scinote::ElnUi::DesignVariable.create!(experiment: exp, name: '基材牌号', var_type: 'categorical',
                                           constraint: '铝 6061 / 304 不锈钢', position: 1)

    vars = payload(exp, scene[:creator])[:expDesignVars]

    assert_equal 2, vars.size, '变量行数 = 二开表行数'
    assert_equal ['POE 增韧剂', '基材牌号'], vars.map { |v| v[:name] }, '顺序按 position'
    assert_equal '5 ~ 25%', vars.first[:range], '数值区间按 min~max+单位 组装'
    assert_equal 'float', vars.first[:type]
    assert_equal '铝 6061 / 304 不锈钢', vars.last[:constraint]
    assert_equal '—', vars.last[:range], 'categorical 无 min/max → 区间留白（不硬凑）'
  end

  # 业务编号：档案里有人工编号就用它，没填才回落原生系统编码（EX + 主键）。
  # 原生没有「实验编号」业务列，所以这两条都得钉死，否则前后端各写一个。
  def test_business_code_preferred_over_native_code
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    assert_equal exp.code.to_s, payload(exp, scene[:creator])[:expInfo][:code], '无档案 → 回落原生 EX+id'

    Scinote::ElnUi::ExperimentProfile.create!(experiment: exp, business_code: 'ELN-EXP-2026-001')
    assert_equal 'ELN-EXP-2026-001', payload(exp, scene[:creator])[:expInfo][:code],
                 '有档案 → 用人工业务编号'
  end

  # addon 自有表没建成（老实例）时，payload 必须降级成留白，而不是整页 500。
  # ⚠ 这个环境**没有** mocha/rspec-mocks（`allow(...)` 会 NoMethodError），
  #   所以用 Ruby 原生的 singleton_method 临时把 table_exists? 改成 false，跑完在
  #   ensure 里摘掉 —— 不留全局副作用给后面的测试。
  def test_payload_survives_when_addon_tables_absent
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    dcls = Scinote::ElnUi::DesignVariable
    pcls = Scinote::ElnUi::ExperimentProfile
    [dcls, pcls].each do |cls|
      cls.singleton_class.send(:define_method, :table_exists?) { false }
    end

    begin
      data = payload(exp, scene[:creator])
    ensure
      [dcls, pcls].each do |cls|
        cls.singleton_class.send(:remove_method, :table_exists?)
      end
    end

    assert_equal [], data[:expDesignVars], '表不存在 → 空数组，不抛错'
    assert_equal '', data[:expMethod], '表不存在 → 方法留白，不抛错'
  end

  # 两张表必须在、且表名是 eln_ui_*（字面上证明「没往原生表里塞东西」）。
  def test_addon_owns_its_own_tables_and_never_touches_native_ones
    assert Scinote::ElnUi::ExperimentProfile.table_exists?, 'eln_ui_experiment_profiles 必须存在'
    assert Scinote::ElnUi::DesignVariable.table_exists?, 'eln_ui_design_variables 必须存在'
    assert_equal 'eln_ui_experiment_profiles', Scinote::ElnUi::ExperimentProfile.table_name
    assert_equal 'eln_ui_design_variables', Scinote::ElnUi::DesignVariable.table_name
    # 原生实验表列数：本 addon 只允许新增自有表，不许 ALTER experiments
    assert_equal 21, ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM information_schema.columns WHERE table_name='experiments'"
    ).to_i, '实验页二开不得给原生 experiments 加列'
  end

  # DEC-001：组员**看不到**「实验设计与配方优化」入口（有管理权限才给）。
  def test_design_tab_is_cut_by_host_permission
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])

    denied = Scinote::ElnUi::ExpDetailPayload.call(exp, scene[:creator], can_manage_experiment: false)
    assert_equal false, denied[:expSubTabs].any? { |t| t[:key] == 'design' }, '无管理权限 → 不给 design 入口'
    assert_equal false, denied[:canManageExperiment]

    allowed = Scinote::ElnUi::ExpDetailPayload.call(exp, scene[:creator], can_manage_experiment: true)
    assert_equal true, allowed[:expSubTabs].any? { |t| t[:key] == 'design' }, '有管理权限 → 给 design 入口'
    assert_equal true, allowed[:canManageExperiment]
    # 三个原生存在的页签不管权限都在
    assert_equal %w[info purpose method], allowed[:expSubTabs].map { |t| t[:key] }.first(3)
  end

  # 首屏必须是真任务表（PRD §7.7「tasks 默认选中」）——
  # 原型的默认左栏页签是 overview，首屏会渲染那块**原型硬编码的假执行步骤**。
  def test_default_nav_is_tasks_and_title_comes_from_real_data
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])

    data = payload(exp, scene[:creator])

    assert_equal 'tasks', data[:expDefaultNav], '默认左栏页签 = tasks（原生任务列表）'
    assert_equal exp.name.to_s, data[:experimentName], '标题来自实验真名'
    assert_equal scene[:project].name.to_s, data[:projectName], '面包屑项目名来自真项目'
    assert_includes %w[active notstarted done], data[:status], '实验三态由 started_at/done_at 推导'
    assert_includes %w[进行中 未开始 已完成], data[:statusText], '徽标文案落在原型状态字典内'
  end

  # 「实验信息」面板 7 格（画布 4:69 hidden 态）以前全是原型**硬编码假值**
  # （EX1 / 硅胶配方与固化体系筛选 / 张负责人 / 2026-09-30 / 1/3 任务）。
  # 整页其它位置都接真了，只留这一块假数据 = 同一屏里自相矛盾，所以这里逐格钉死来源。
  def test_info_pane_fields_come_from_real_data
    scene = build_scene!
    project = scene[:project]
    exp = make_experiment!(project: project, creator: scene[:creator])
    task = make_task!(experiment: exp, creator: scene[:creator])
    ensure_default_status_flow!
    exp.update_columns(due_date: Date.new(2026, 10, 31))

    info = payload(exp, scene[:creator])[:expInfo]

    assert_equal exp.code.to_s, info[:code], '编号取原生 Experiment#code（前缀 EX + 主键）'
    assert_equal exp.name.to_s, info[:name], '名称 = experiments.name'
    assert_equal scene[:project].name.to_s, info[:project], '所属项目 = projects.name'
    assert_equal scene[:creator].full_name.to_s, info[:owner], '负责人 = 实验指派人（无则创建者）'
    assert_equal '2026-10-31', info[:due], '计划完成 = experiments.due_date（YYYY-MM-DD）'
    # 任务进度是**推导**不是编造：默认状态流三档里「Completed」才是已完成。
    assert_match(/\A\d+\/\d+ 任务\z/, info[:progress], '进度形如 n/m 任务（分母=本实验任务总数）')
    assert_includes %w[进行中 未开始 已完成], info[:state], '状态文案落在原型状态字典内'
    assert_match(%r{\Avar\(--status-(notstarted|active|done)\)\z}, info[:stateColor],
                 '状态色是 tokens.css 里真实存在的三档变量之一')
  end

  # 原生没有「实验负责人」这一列，也没有 due_date 时不能凭空造一个日期 /
  # 一个人名，得显式留白（'—'），否则页面看着很满其实全是假的。
  def test_info_pane_blank_when_native_has_no_value
    scene = build_scene!
    # ⚠ run_inherit: false —— 不给实验挂 UserAssignment，负责人就只能落到创建者；
    #   下面再手动把创建者摘掉，模拟「原生既无指派也无创建者可读」。
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    exp.update_columns(due_date: nil)

    # ⚠ 构造「完全没人负责」必须**两层都摘掉**，不能指望 run_inherit: false：
    #   即使不继承项目成员，D3「创建者自动可见」仍会给实验挂一条 creator 的
    #   UserAssignment（assignable_type='Experiment'）—— 实测 ua=1，
    #   那样 owner 走的是「指派人」这一级，返回的是**真值** creator，不是留白。
    #   ⚠ created_by 只能**内存**置空：experiments.created_by_id 是 NOT NULL，
    #     update_columns(created_by_id: nil) 直接 PG::NotNullViolation。
    exp.user_assignments.where(assignable_type: 'Experiment').delete_all
    exp.created_by = nil

    info = Scinote::ElnUi::ExpDetailPayload.call(exp, scene[:creator],
                                                 can_create_task: true,
                                                 can_manage_experiment: false)[:expInfo]

    assert_equal '—', info[:owner], '原生无负责人 → 显式留白，不许编造人名'
    assert_equal '—', info[:due], 'due_date 为空 → 显式留白，不许编造日期'
    assert_equal '0/0 任务', info[:progress], '无任务时进度是 0/0（真值，不是 1/3 那套假值）'
  end

  # 视图侧挂载契约：与列表页同一套，两边任一改名这条立刻红。
  def test_exp_detail_page_mounts_vue_bundle
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])

    html = open_exp(exp, scene[:creator])

    assert_equal 200, @status, '成员应能打开实验详情页'
    assert_includes html, 'id="eln-exp-detail"', '挂载点必须存在'
    assert_includes html, 'id="eln-exp-detail-data"', '数据注入块必须存在'
    # ⚠ 断言**不能带扩展名**：precompile 后 HTML 里是 digest 文件名
    #   （eln_exp_detail-<hash>.js/.css），写 'eln_exp_detail.js' 永远红。
    assert_includes html, 'eln_exp_detail', 'Vue bundle 必须被引入'
    assert_includes html, exp.name, '页面必须带真实验名'
  end

  # 不可读的实验必须走原生 404 语义，不能自己 render 一个「无权限」页面
  # （否则和原生行为分叉，用户会看到两套错误页）。
  def test_unreadable_experiment_raises_not_found
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    outsider = scene[:outsider] || User.order(:id).where.not(id: scene[:creator].id).first

    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(outsider, scope: :user) }
    session.get("/experiments/#{exp.id}/eln_exp_detail")

    assert_includes [404, 403], session.response.status,
                    "读不到的实验应返回原生 404/403，实际 #{session.response.status}"
  end


  # ============================================================
  # 下钻URL（2026-10-05）
  # ============================================================

  # 任务行必须带 addon 任务详情页的真实地址；
  # 原型那条 to="/tasks/:id" 落进 SciNote 是死链（原生任务挂在实验两级之下）。
  def test_task_rows_carry_real_task_detail_url
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    mod = make_task!(experiment: exp, creator: scene[:creator])

    payload = Scinote::ElnUi::ExpDetailPayload.call(exp, scene[:creator])
    row = payload[:tasks].find { |t| t[:id] == mod.id.to_s }
    refute_nil row, 'payload 里必须有这条任务'
    assert_equal "/experiments/#{exp.id}/my_modules/#{mod.id}/eln_task_detail", row[:detailUrl]
  end

  # 面包屑第二级「项目名」要能点回该项目 ——原来前端写死 to="/projects/PR1025240"
  def test_crumb_carries_project_detail_url
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])

    payload = Scinote::ElnUi::ExpDetailPayload.call(exp, scene[:creator])
    assert_equal "/projects/#{scene[:project].id}/eln_project_detail", payload[:projectDetailUrl]
  end

  # 原生实验页地址（去原生页的旁路）必须保留在实验行 href 里——
  #   别为了加 detailUrl 把旧的删了，用户有时就想去原生页。
  def test_experiment_row_keeps_native_href_alongside_detail_url
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])

    payload = Scinote::ElnUi::ProjectDetailPayload.call(scene[:project])
    row = payload[:experiments].find { |e| e[:id] == exp.id }
    refute_nil row
    assert_equal "/projects/#{scene[:project].id}/experiments/#{exp.id}", row[:href],
                 '原生旁路 href 必须保留'
    assert_equal "/experiments/#{exp.id}/eln_exp_detail", row[:detailUrl],
                 'addon 详情页地址必须同时给出'
  end

  private

  # ⚠ 测试库里默认没有 MyModuleStatus 行（生产库有：SciNote Free default task flow
  #   三档）。MyModuleStatus belongs_to :my_module_status_flow 必填，
  #   自己硬造一个状态行很脆 —— 直接用原生 seeding 用的入口，建出来的就是真那三档。
  def ensure_default_status_flow!
    # ⚠ 方法名是 ensure_default（不是 ensure_default!）—— 原生 app/models/my_module_status_flow.rb:25
    MyModuleStatusFlow.ensure_default unless MyModuleStatusFlow.exists?
  end

  def payload(exp, user)
    Scinote::ElnUi::ExpDetailPayload.call(exp, user, can_create_task: true, can_manage_experiment: false)
  end
  def open_exp(exp, user)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.get("/experiments/#{exp.id}/eln_exp_detail")
    @status = session.response.status
    session.response.body
  end
end
