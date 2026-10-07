# frozen_string_literal: true
#
# ELN UI —— 测试表征「逾期未回填」账本 + 原生任务完成闸门（REQ-RES-TEST-STRIKE）
#
# 守 5 件事（全部落在 spec V1.21 的相关条目上，别在别处打折）：
#   1. **账只有一本**：ServiceStrikeBook 只回答「算出来的账」（谁欠、欠几个、
#      欠什么），要不要拦、拦了说啥由调用方决定 —— 申请入口与完成闸门共用它，
#      不许两处各算一遍（L1030）；
#   2. **未回填** = 服务执行行 `result_file` 空（结果文件必须以 ResultAsset 显式
#      绑到该次执行的任务 Results，L998，只「传了但没绑」不算回填）；
#   3. **已到期** = 执行行 `occurred_at` 起超过 `service_result_grace_days`（L1021，
#      可配，默认 30）；宽限期内不欠 —— 别把「刚做完还没传」当成欠交；
#   4. **冻结只针对测试表征**（L1030），材料申请照常入；管理员豁免**放行一次**
#      且**不消解占用**（L1035）；
#   5. **配置即时生效**（L1031）：管理员改阈值/宽限后，冻结判定当次就按新值算，
#      不许靠重启进程兜。

require_relative 'test_helper'

class ElnUiServiceStrikeTest < AcTest::Base
  include ElnUiFactories

  WF   = Scinote::ElnUi::ResourceApplicationWorkflow
  BOOK = Scinote::ElnUi::ServiceStrikeBook
  CR   = Scinote::ElnUi::ConsumeRecord

  def configure!(grace:, limit:)
    AddonSetting.update_for('eln_ui', enabled: true,
                            configuration: { 'service_result_grace_days' => grace,
                                             'service_result_strike_limit' => limit })
  end

  def make_reviewer!(scene)
    user = make_user!(name: 'reviewer')
    join_team!(user, scene[:team])
    user
  end

  def wf!(user, scene, app, type)
    WF.call(user: user, team: scene[:team], no: app.no, type: type)
  end

  # 走完二段式审批 → 标记完成 → 该服务执行登记一行服务行。
  # ⚠ 必须真走 complete：服务行只在 complete 那一刻登记（SCN-RES-TEST-1），
  #   手搓 ConsumeRecord 会绕过闸门链，测出来的账和线上不是一回事。
  def make_serviced_app!(scene:, task: nil, name: 'DSC 差示扫描量热')
    catalog = make_service_catalog!(name: name)
    args = { user: scene[:creator], team: scene[:team],
             project_id: scene[:project].id, kind: 'service', name: catalog.name,
             qty: '2', unit: '次', service_catalog_id: catalog.id }
    args[:my_module_id] = task.id if task
    result = WF.create_draft(**args)
    app = Scinote::ElnUi::ResourceApplication.find_by!(no: result[:no])
    mate = make_reviewer!(scene)
    # 闸门已 fail-closed：mate 必须先在审批名单里，不然 approve_* 一律被挡
    configure_approver!(user: mate, project: scene[:project])
    wf!(app.requestor, scene, app, 'submit')
    wf!(mate, scene, app, 'approve_group')
    wf!(mate, scene, app, 'approve_project')
    wf!(mate, scene, app, 'complete')
    app
  end

  # 服务行（source 就是刚完成的申请单）+ 可回溯的执行时刻 / 回填结果
  def service_row_for!(app, occurred_at:, resulted: false)
    row = CR.find_by!(source_type: CR::SERVICE_SOURCE_TYPE, source_id: app.id)
    row.update!(occurred_at: occurred_at, result_file: resulted ? 'DSC 曲线.pdf' : nil)
    row
  end

  def days_ago(n) = Time.current - n.days

  # ⚠ 别写 assert_nothing_raised：宿主 Canaid 的 method_missing 会把**任何**非
  #   `can_*?` 方法吞成 NoMethodError（老坑），断言假红。这里用显式捕获取返回。
  def caught_error
    yield
    nil
  rescue StandardError => e
    e
  end

  # ------------------------------------------------------------
  # ① 账：什么时候算「欠交」
  # ------------------------------------------------------------

  # L1021 宽限期内不算欠 —— 刚做完还没传结果的人不该被计入占用，
  # 否则「宽限期」这个可配项就成了摆设（默认 30 天，5 天前属窗口内）。
  def test_not_overdue_within_grace_window
    scene = build_scene!
    configure!(grace: 30, limit: 10)
    app = make_serviced_app!(scene: scene)
    service_row_for!(app, occurred_at: days_ago(5))

    assert_empty BOOK.for_applicant(scene[:creator].id),
                 '宽限期内（5 天）未回填不计入未消解占用'
  end

  def test_overdue_after_grace_window_without_result
    scene = build_scene!
    configure!(grace: 30, limit: 10)
    app = make_serviced_app!(scene: scene)
    service_row_for!(app, occurred_at: days_ago(31))

    overdue = BOOK.for_applicant(scene[:creator].id)
    assert_equal 1, overdue.size, '超期 + 未回填 = 1 条未消解占用'
  end

  # L998：只「上传了但没绑到该次执行」不算回填；绑了（result_file 有值）才消解。
  def test_result_file_clears_the_debt
    scene = build_scene!
    configure!(grace: 30, limit: 10)
    app = make_serviced_app!(scene: scene)
    service_row_for!(app, occurred_at: days_ago(31), resulted: true)

    assert_empty BOOK.for_applicant(scene[:creator].id),
                 '结果已回填（ResultAsset 显式绑到该次执行）→ 占用消解'
  end

  def test_for_task_scopes_to_that_task_only
    scene = build_scene!
    configure!(grace: 30, limit: 10)
    task_a = build_task_for(scene)
    task_b = build_task_for(scene)
    app_a = make_serviced_app!(scene: scene, task: task_a, name: 'DSC 差示扫描量热')
    app_b = make_serviced_app!(scene: scene, task: task_b, name: 'XRF 元素分析')
    service_row_for!(app_a, occurred_at: days_ago(40))
    service_row_for!(app_b, occurred_at: days_ago(40))

    # ⚠ 完成闸门只看「这个任务欠了什么」—— 把别的任务的欠交算进来，
    #   就会在任务完成时拦一个跟它无关的人。
    assert_equal 1, BOOK.for_task(task_a).size, '闸门只统计本任务的执行单'
    assert_equal 1, BOOK.for_task(task_b).size
    assert_equal 2, BOOK.for_applicant(scene[:creator].id).size
  end

  # ------------------------------------------------------------
  # ② 冻结与原因（L1030）
  # ------------------------------------------------------------

  def test_reaching_limit_freezes_and_reason_lists_threshold
    scene = build_scene!
    configure!(grace: 30, limit: 2)
    app1 = make_serviced_app!(scene: scene, name: 'DSC 差示扫描量热')
    app2 = make_serviced_app!(scene: scene, name: '冲击试验')
    service_row_for!(app1, occurred_at: days_ago(40))
    service_row_for!(app2, occurred_at: days_ago(41))

    assert_equal true, BOOK.frozen?(scene[:creator].id),
                 '未消解占用 ≥ 阈值 → 冻结该申请人'
    reason = BOOK.block_reason(scene[:creator].id)
    assert_match(/2/, reason)
    # ⚠ 两个坑一起躲：① 阈值这类中文串用字符串做匹配参数（正则字面量后接第三个
    #   实参会被解析器当成位移运算）；② minitest 的失败说明是**第三个实参**，
    #   不是 `assert_match(a, b), 'msg'` 这种尾巴上再挂一个（后者 SyntaxError）。
    assert_match('阈值 2', reason, '原因必须写明阈值（L1030「展示原因、阈值与欠交清单」）')
    assert_match('DSC 差示扫描量热', reason, '原因里要有欠交清单')
    assert_match(/冲击试验/, reason)
  end

  # 没冻结时 block_reason 返回 nil —— 用 nil 而不是空串，
  # 免得调用方写出「冻结了但没理由」的岔路。
  def test_block_reason_is_nil_when_not_frozen
    scene = build_scene!
    configure!(grace: 30, limit: 10)

    assert_nil BOOK.block_reason(scene[:creator].id), '未达阈值 → 无冻结原因（nil 不是空串）'
  end

  # ------------------------------------------------------------
  # ③ 配置即时生效（L1031）
  # ------------------------------------------------------------

  # ⚠ 这条专门守「不缓存」：改完配置不重启进程，判定就要跟着变。
  def test_config_change_takes_effect_immediately
    scene = build_scene!
    configure!(grace: 30, limit: 10)
    app = make_serviced_app!(scene: scene)
    service_row_for!(app, occurred_at: days_ago(31))
    assert_equal 1, BOOK.for_applicant(scene[:creator].id).size, '默认宽限 30 天 → 超期'

    configure!(grace: 60, limit: 10)
    assert_empty BOOK.for_applicant(scene[:creator].id),
                 '管理员把宽限改成 60 天后，同一条行立刻不再欠（L1031 即时生效）'

    configure!(grace: 30, limit: 10)
    assert_equal 1, BOOK.for_applicant(scene[:creator].id).size, '再改回来判定也要跟着回来'
  end

  # ------------------------------------------------------------
  # ④ 管理员豁免（L1035）
  # ------------------------------------------------------------

  # ⚠ 豁免是「放行一次」，不是「消解占用」：
  #   L1035 明写豁免不改变未回填事实、用后即失效。
  def test_waiver_passes_once_and_does_not_clear_debt
    scene = build_scene!
    configure!(grace: 30, limit: 1)
    app = make_serviced_app!(scene: scene)
    service_row_for!(app, occurred_at: days_ago(40))

    assert_equal true, BOOK.frozen?(scene[:creator].id)

    admin = make_reviewer!(scene)
    BOOK.grant_waiver!(user: scene[:creator], granted_by: admin, reason: '设备检修延期')

    assert_equal true, BOOK.frozen?(scene[:creator].id), '发放豁免本身不消解占用'
    assert_equal true, BOOK.consume_waiver!(scene[:creator].id), '用掉豁免 → true'
    assert_equal false, BOOK.consume_waiver!(scene[:creator].id), '用过一次即失效，第二次返回 false'
    assert_equal true, BOOK.frozen?(scene[:creator].id), '豁免用完，占用仍在 → 依旧冻结'
  end

  # ------------------------------------------------------------
  # ⑤ 申请入口：冻结拦测试表征，放行材料（L1030）
  # ------------------------------------------------------------

  def test_frozen_applicant_cannot_create_service_application
    scene = build_scene!
    configure!(grace: 30, limit: 1)
    app = make_serviced_app!(scene: scene)
    service_row_for!(app, occurred_at: days_ago(40))

    err = assert_raises(WF::WorkflowError) do
      WF.create_draft(user: scene[:creator], team: scene[:team],
                      project_id: scene[:project].id, kind: 'service',
                      name: '万能试验机拉伸', qty: '1',
                      service_catalog_id: make_service_catalog!(name: '万能试验机拉伸').id)
    end
    assert_match('未回填测试表征结果占用', err.message, '拒绝原因要能直接展示给用户')
  end

  # 一刀切地连材料申请也挡了是错的 —— spec 封禁的对象是「提交新的测试表征申请」。
  def test_material_application_still_allowed_while_frozen
    scene = build_scene!
    configure!(grace: 30, limit: 1)
    app = make_serviced_app!(scene: scene)
    service_row_for!(app, occurred_at: days_ago(40))

    result = WF.create_draft(user: scene[:creator], team: scene[:team],
                             project_id: scene[:project].id, kind: 'material',
                             name: '滑石粉', qty: '10', unit: 'kg', unit_price: 12,
                             repository_id: target_repository_id(team: scene[:team], creator: scene[:creator]))
    assert_equal true, result[:ok]
  end

  # 冻结被豁免放行：能建单，且**只放行这一次**（豁免在该次请求里被用掉）。
  def test_waiver_releases_one_frozen_submission
    scene = build_scene!
    configure!(grace: 30, limit: 1)
    app = make_serviced_app!(scene: scene)
    service_row_for!(app, occurred_at: days_ago(40))
    BOOK.grant_waiver!(user: scene[:creator], granted_by: make_reviewer!(scene), reason: '项目加急')

    result = WF.create_draft(user: scene[:creator], team: scene[:team],
                             project_id: scene[:project].id, kind: 'service',
                             name: '万能试验机拉伸', qty: '1',
                             service_catalog_id: make_service_catalog!(name: '万能试验机拉伸').id)
    assert_equal true, result[:ok]

    assert_raises(WF::WorkflowError) do
      WF.create_draft(user: scene[:creator], team: scene[:team],
                      project_id: scene[:project].id, kind: 'service',
                      name: 'XRF 元素分析', qty: '1',
                      service_catalog_id: make_service_catalog!(name: 'XRF 元素分析').id)
    end
  end

  # ------------------------------------------------------------
  # ⑥ 原生任务完成闸门（L1040 / SCN-RES-TEST-STRIKE-4）
  # ------------------------------------------------------------

  # ⚠ 后果是 STI 子类：类必须挂在 MyModuleStatusConsequence 名下，
  #   my_module_status_consequences.type 才会认得 'MyModuleStatusConsequences::ServiceResultGate'。
  def test_gate_is_a_native_consequence_subclass
    assert_equal true, MyModuleStatusConsequence > MyModuleStatusConsequences::ServiceResultGate,
                 '闸门必须是 MyModuleStatusConsequence 的子类（否则 type 列认不出，闸门白挂）'
  end

  def test_gate_blocks_forward_with_overdue_list
    scene = build_scene!
    configure!(grace: 30, limit: 10)
    task = build_task_for(scene)
    app = make_serviced_app!(scene: scene, task: task)
    service_row_for!(app, occurred_at: days_ago(40))

    err = assert_raises(MyModuleStatus::MyModuleStatusTransitionError) do
      MyModuleStatusConsequences::ServiceResultGate.new.forward(task)
    end
    assert_equal :service_result, err.error[:type]
    assert_equal 1, err.error[:missing].size, '错误载荷要带欠交清单（L1040）'
    assert_match(/DSC 差示扫描量热/, err.error[:missing].first)
    assert_match('回填', err.error[:message], '要有一句能直接显示给用户的 message')
  end

  # nothing overdue → 放行（闸门不该把正常任务也拦下）
  def test_gate_allows_forward_when_everything_backfilled
    scene = build_scene!
    configure!(grace: 30, limit: 10)
    task = build_task_for(scene)
    app = make_serviced_app!(scene: scene, task: task)
    service_row_for!(app, occurred_at: days_ago(40), resulted: true)

    assert_nil caught_error { MyModuleStatusConsequences::ServiceResultGate.new.forward(task) },
               '结果都回填了 → 闸门放行'
  end

  # 往回退不拦 —— SCN-RES-TEST-STRIKE-4 只约束「标记为完成」这一刻，
  # 撤销误操作不该被自己的闸门挡住。
  def test_backward_is_never_blocked
    scene = build_scene!
    configure!(grace: 30, limit: 10)
    task = build_task_for(scene)
    app = make_serviced_app!(scene: scene, task: task)
    service_row_for!(app, occurred_at: days_ago(40))

    assert_nil caught_error { MyModuleStatusConsequences::ServiceResultGate.new.backward(task) },
               '回退方向（SCN-RES-TEST-STRIKE-4）不设闸门'
  end
end
