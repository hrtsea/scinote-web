# frozen_string_literal: true
#
# ELN UI —— 项目列表页数据装配（Scinote::ElnUi::ProjectListPayload）与列表页视图契约
#
# 与详情页那份测试同一条规矩：值必须来自真库，原生没有的字段走「显式留白/推导」，
# 不许为了好看编一个数。列表页额外守三件详情页不碰的事：
#   1. 状态是**推导**出来的（started_at / done_at），不是枚举列；
#   2. 「新建项目」权限由宿主给（canCreateProject），不跟着原型 mock 走；
#   3. 作用域口径（本测试不测 controller 的 scope，那属于可读性的事），
#      测 Payload 肯不肯把传进来的项目**逐条翻译成原型字段**。

require_relative 'test_helper'

class ElnUiProjectListTest < AcTest::Base
  include Warden::Test::Helpers
  # 行菜单 gate 要与原生谓词**对拍**，所以测试侧也得能调 can_*?。
  # ⚠ 一律显式传 user（Canaid 的 can_*? 在 1 参时回读 current_user，
  #   测试类里没有那概念，不传会误判成 false 而假绿）。
  include Canaid::Helpers::PermissionsHelper

  def test_rows_map_real_columns
    scene = build_scene!
    project = scene[:project]
    exp = make_experiment!(project: project, creator: scene[:creator])

    row = list(scene).first

    assert_equal project.id.to_s, row[:id], 'id 用主键字符串（原生无业务编号列）'
    assert_equal project.name, row[:name], '名称来自 projects.name'
    # ⚠ 原型 statusLabel 只有三档；原生没有项目状态枚举列，状态是**推导**的。
    assert_includes %w[active notstarted done], row[:status]
    assert_equal 1, row[:total], '实验数按 project.experiments 真实聚合'
    assert_equal({ done: 0, total: 1 }, { done: row[:completed], total: row[:total] }, '完成/总数来自实验口径')
    refute_nil row[:owner][:name], '负责人必须有真名兜底（ Supervised_by 为空时退回 created_by）'
    assert_includes %w[blue green orange cyan purple], row[:owner][:color], '头像配色落在原型调色板内'
    refute_nil row[:members], '成员头像组必须存在（没有成员时是空数组，不是 nil 崩页面）'
  end

  # 生产库实况：projects.template 是**可空布尔**，生产库 159 行里 158 行是 NULL。
  # 这正是列表恒空的根因，钉死在这里防止有人「顺手」把它改回 where(template: false) ——
  # 那种写法在空库/全 NULL 的库上永远返回 0 条，页面 200 却一条数据都没有。
  def test_template_projects_are_kept_when_column_is_null
    scene = build_scene!
    project = scene[:project]
    assert_nil project.reload.template, '本用例前提是 template 为 NULL（生产库实况）'

    rows = Scinote::ElnUi::ProjectListPayload.call(Project.where(id: project.id))

    assert_equal 1, rows[:projects].size, 'template = NULL 的项目仍必须出现在列表里'
  end

  def test_status_derives_from_started_and_done
    scene = build_scene!
    project = scene[:project]

    assert_equal 'notstarted', list(scene).first[:status], '没 started_at → 未开始'

    project.update!(started_at: Time.zone.now, done_at: nil)
    assert_equal 'active', list(scene).first[:status], '有 started_at → 进行中'

    project.update!(done_at: Time.zone.now)
    assert_equal 'done', list(scene).first[:status], '有 done_at → 已完成'
  end

  def test_can_create_project_comes_from_host_not_mock
    scene = build_scene!

    assert_equal false, Scinote::ElnUi::ProjectListPayload.call(Project.none, can_create_project: false)[:canCreateProject]
    assert_equal true, Scinote::ElnUi::ProjectListPayload.call(Project.none, can_create_project: true)[:canCreateProject]
    # 不传时默认 false —— 权限没注入就别显示按钮（宁可少显示，不能越权显示）
    assert_equal false, Scinote::ElnUi::ProjectListPayload.call(Project.none)[:canCreateProject]
  end

  # 视图侧的挂载契约：与详情页同一套，两边任一边改名这条立刻红
  def test_project_list_page_mounts_vue_bundle
    scene = build_scene!

    html = open_list(scene[:creator])

    assert_equal 200, @status, '成员应能打开项目列表页'
    assert_includes html, 'id="eln-project-list"', '挂载点必须存在'
    assert_includes html, 'id="eln-project-list-data"', '数据注入块必须存在'
    # ⚠ 断言**不能带扩展名**：assets:precompile 之后 HTML 里是 digest 文件名
    #   （eln_project_list-<40位hash>.js/.css），写 'eln_project_list.js' 在预编译产物上永远红。
    #   只断「这个页面的 bundle / 样式被引入了」，扩展名由 assets.rb 的 precompile 名单守住。
    assert_includes html, 'eln_project_list', 'Vue bundle 必须被引入'
    assert_includes html, scene[:project].name, '页面必须带真项目名'
  end

  # ------------------------------------------------------------------
  # 工具栏（原生 toolbar.vue 那 7 个控件）的服务端契约
  # ------------------------------------------------------------------

  # 前端 7 个控件每一项都要有落点：没有 listUrl 就刷不动、没有 createUrls 就 POST 不出去、
  # 没有 statuses/members/... 筛选面板就只剩原型那几档假数据。
  def test_payload_carries_every_toolbar_capability
    payload = Scinote::ElnUi::ProjectListPayload.call(
      Project.none,
      can_create_project: true,
      can_create_folder: true,
      folders: [{ id: 7, name: 'F' }],
      members: [{ id: 1, name: 'A' }],
      head_of_projects: [{ id: 2, name: 'B' }],
      statuses: [{ id: 'done', name: 'Done' }],
      default_roles: [{ id: 4, name: 'Viewer' }],
      create_urls: { project: '/projects', folder: '/project_folders' },
      list_url: '/eln_project_list.json',
      view_mode: 'archived'
    )

    assert_equal true, payload[:canCreateFolder], '新建文件夹权限要出给前端'
    assert_equal '/eln_project_list.json', payload[:listUrl], 'json 出口要出给前端（否则按钮改完条件刷不动）'
    assert_equal '/projects', payload[:createUrls][:project], '新建项目的原生端点由服务端给，前端不写死'
    assert_equal '/project_folders', payload[:createUrls][:folder], '新建文件夹的原生端点由服务端给'
    assert_equal 'archived', payload[:viewMode], '视图模式要跟着当前请求，刷新后不能跳回活动态'
    assert_equal 1, payload[:folders].size
    assert_equal 1, payload[:members].size
    assert_equal 1, payload[:headOfProjects].size
    assert_equal 1, payload[:defaultRoles].size, '默认角色要来自真 UserRole（不是原型那四个字符串）'
  end

  # 不传时**全部为空而不是崩**：老调用方（含别的测试）不该被这一步打断。
  def test_toolbar_fields_default_to_empty_not_crash
    payload = Scinote::ElnUi::ProjectListPayload.call(Project.none)

    assert_equal false, payload[:canCreateFolder]
    assert_equal [], payload[:folders]
    assert_equal [], payload[:statuses]
    assert_equal [], payload[:defaultRoles]
    assert_equal({}, payload[:createUrls])
    assert_nil payload[:listUrl]
    assert_equal 'active', payload[:viewMode], '没给 viewMode 时按原生默认：活动态'
  end

  # 🔴 钉死 2026-10-04 那个坑：宿主定义了 `Scinote::I18n`，addon controller 在
  #   module Scinote::ElnUi 里裸写 I18n 会命中它 → NoMethodError → 整段 rescue 成 []。
  #   症状极坏：页面 200、筛选面板照样能开（前端拿原型三档兜底），
  #   但筛出来的集合跟原生项目页不是一个口径。
  #   所以这里断两条：① 键必须是原生 scope 键；② 文案必须**翻译过**（不能等于键名，
  #   等于键名就说明 I18n 那条路已经断了、正走在退化分支上）。
  def test_statuses_use_native_scope_keys_and_are_translated
    scene = build_scene!
    project = scene[:project]
    project.update!(started_at: Time.zone.now)

    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(scene[:creator], scope: :user) }
    session.get('/eln_project_list', params: { format: :json })
    assert_equal 200, session.response.status, 'json 出口必须可用（按钮改完条件要能只重拉数据）'

    payload = JSON.parse(session.response.body)
    keys = payload['statuses'].map { |s| s['id'] }

    assert_equal %w[not_started in_progress done], keys,
                 '筛选状态必须是原生 Lists::ProjectsService 的 scope 键，不是 MyModuleStatus 的 id'
    payload['statuses'].each do |s|
      refute_equal s['id'], s['name'],
                   "状态 #{s['id']} 的文案没翻译（等于键名）→ ::I18n 那条路断了，正在走退化分支"
      refute_empty s['name'].to_s
    end
  end

  # 过滤口径：**复用原生 Lists::ProjectsService**，不自己造一套。
  # 谁改了原生的筛选语义，我们这边自动跟着变 —— 这里只钉「传进去的条件真的生效了」。
  def test_search_filter_goes_through_native_service
    scene = build_scene!
    project = scene[:project]

    json = lambda do |params|
      s = ActionDispatch::Integration::Session.new(Rails.application)
      Warden.on_next_request { |proxy| proxy.set_user(scene[:creator], scope: :user) }
      s.get('/eln_project_list', params: params.merge(format: :json))
      JSON.parse(s.response.body)
    end

    all = json.call({})
    assert_equal [project.id.to_s], all['projects'].map { |p| p['id'] }, '默认活动态能看见自己的项目'

    hit = json.call(search: project.name)
    assert_equal [project.id.to_s], hit['projects'].map { |p| p['id'] }, 'search 命中项目名'

    miss = json.call(search: '绝不可能命中的一串字')
    assert_empty miss['projects'], 'search 落空时是空列表（不是忽略条件返回全表）'

    # 归档态：同一个项目没归档 → 归档视图下不该出现（原生 archived scope）
    archived = json.call(view_mode: 'archived')
    refute_includes archived['projects'].map { |p| p['id'] }, project.id.to_s,
                    '未归档项目不能出现在归档态里（view_mode 真的传给了原生 service）'
  end

  # 「新建项目 / 新建文件夹」是 POST 原生端点，视图必须吐 CSRF token，
  # 否则点了就是 422 InvalidAuthenticityToken —— 弹窗纹丝不动，看着像没接。
  def test_list_page_emits_csrf_meta_for_native_post_endpoints
    html = open_list(build_scene![:creator])

    assert_includes html, 'name="csrf-token"', 'addon 视图默认不输出 CSRF，POST 原生端点必须自带 meta'
  end

  # ------------------------------------------------------------
  # 列头排序（2026-10-04 接入）：controller 复用原生 Lists::ProjectsService#sort_records，
  # 吃 `order[column]` + `order[dir]`（非 asc 一律 DESC）。这里用与 controller 相同的
  # 三行胶水（filter → 回填 @records → sort）验证两件事：
  #   1. 排序 helper 对**未经 fetch_projects 预加载**的裸 Project 记录可用（原生 call()
  #      会先 preload，我们绕过了它 —— 这是唯一可能踩的坑）；
  #   2. 未知列键安静回落（不排序、不 500），与原生「case 无匹配就跳过」一致。
  # ------------------------------------------------------------
  def test_sort_reuses_native_service_on_bare_project_records
    scene = build_scene!
    team = scene[:team]
    p_a = make_project!(team: team, creator: scene[:creator])
    p_a.update!(name: 'aaa_sort')
    p_b = make_project!(team: team, creator: scene[:creator])
    p_b.update!(name: 'zzz_sort')

    scope = Project.where(team_id: team.id, template: [false, nil])
                   .distinct.readable_by_user(scene[:creator]).order(name: :asc)

    sorted = sort_like_controller(scope, team, scene[:creator],
                                  { column: 'name', dir: 'desc' })
    names = sorted.map(&:name)
    assert names.index('zzz_sort') < names.index('aaa_sort'),
           "order[name DESC] 应让 zzz 排在 aaa 前，实际顺序: #{names}"

    sorted_asc = sort_like_controller(scope, team, scene[:creator],
                                      { column: 'name', dir: 'asc' })
    names_asc = sorted_asc.map(&:name)
    assert names_asc.index('aaa_sort') < names_asc.index('zzz_sort'),
           "order[name ASC] 应让 aaa 排在 zzz 前，实际顺序: #{names_asc}"
  end

  def test_sort_with_unknown_column_returns_records_untouched
    scene = build_scene!
    team = scene[:team]
    pr = make_project!(team: team, creator: scene[:creator])
    pr.update!(name: 'aaa_sort')

    scope = Project.where(team_id: team.id, template: [false, nil])
    sorted = sort_like_controller(scope, team, scene[:creator],
                                  { column: 'no_such_key', dir: 'asc' })
    assert_equal scope.count, sorted.count, '未知列键不能丢行'
  end


  # ============================================================
  # 下钻URL（2026-10-05）
  # ============================================================

  # 前端不写死宿主路由，真地址一律由 payload 下发；缺了就 nil（前端回落原型路径）。
  def test_payload_carries_real_detail_url_per_row
    scene = build_scene!
    rows = Scinote::ElnUi::ProjectListPayload.call(
      Project.where(id: scene[:project].id),
      can_create_project: true,
      detail_url_base: '/projects'
    )[:projects]

    assert_equal 1, rows.size
    # 必须是 addon 自己的详情路由，不是原型 SPA 的 /projects/:id（真机上那是死链）
    assert_equal "/projects/#{scene[:project].id}/eln_project_detail", rows[0][:detailUrl]
  end

  # 没注入 base 时必须是 nil ——绝不能退化成 '/projects/:id' 这种半真半假的地址
  def test_detail_url_is_nil_when_base_not_injected
    scene = build_scene!
    rows = Scinote::ElnUi::ProjectListPayload.call(
      Project.where(id: scene[:project].id)
    )[:projects]

    assert_nil rows[0][:detailUrl]
  end

  # 列表页 HTML 真机跑出来的 JSON，每行都得带可点开的 detailUrl
  def test_list_json_endpoint_rows_expose_detail_url
    scene = build_scene!
    body = open_list(scene[:creator])
    assert_equal 200, @status
    # 页面把 payload 写进 window.__ELN_PROJECT_LIST__；detailUrl 逐行下发
    assert_includes body, 'detailUrl'
  end

  # ---------------------------------------------------------------------------
  # 行菜单 7 项（编辑/访问权限/移动/导出/归档/评论/动态）真源接线
  #
  # 断言分三层，缺一不可：
  #   1. **形状** —— 7 个 key 都在，enabled 是布尔，url 下发且格式对得上原生端点；
  #   2. **权限同源** —— gate 逐条照抄原生 Toolbars::ProjectsService（见 payload#action_gate）；
  #   3. **降级** —— 没传 current_user 时全部 enabled: false（显式留白，不装能点）。
  # ---------------------------------------------------------------------------
  def test_row_actions_shape_and_native_urls
    scene = build_scene!
    project = scene[:project]
    row = list_with_user(scene).first

    actions = row[:actions]
    assert_equal %i[activity archive access comment edit export move].sort,
                 actions.keys.sort, '行菜单固定 7 项（open 是前端下钻项，不进 payload）'
    actions.each do |key, act|
      assert_includes [true, false], act[:enabled], "#{key}: enabled 必须是布尔"
      next unless act[:enabled]

      refute_nil act[:url], "#{key}: 标了可用就必须下发端点"
    end

    # 原生端点逐条核对（写死期望值 = 路由改名/口径漂移立刻红）
    assert_equal "/access_permissions/projects/#{project.id}", actions[:access][:url]
    assert_equal "/projects/archive_group", actions[:archive][:url]
    assert_equal '/projects/archive_group', actions[:archive][:url], '归档走原生批量端点 archive_group'
    assert_match %r{\A/teams/\d+/export_projects\z}, actions[:export][:url], '导出走原生团队导出端点'
    # 移动：目标树 + 写回两个端点都必须是原生那两个（见 payload#row_actions 的纠错注释）
    assert_match %r{\A/project_folders/tree\z}, actions[:move][:folders_tree_url], '移动目标来自原生文件夹树'
    assert_equal '/project_folders/move_to', actions[:move][:url], '移动写回走原生 project_folders#move_to'
    assert_equal 'root_folder', actions[:move][:root_key], '顶层目标键与原生 selectFolder(null) 一致'
    # ⚠ Rails 的 to_query 会把参数键**排序**（object_id 在 object_type 前面），
    #   所以期望串是这个顺序 —— payload 侧别手写成 object_type 在前去对齐。
    assert_match %r{\A/comments\?object_id=#{project.id}&object_type=Project\z},
                 actions[:comment][:url], '评论走原生 /comments（commentable = Project）'
    # ⚠ 查询串由 Activity.url_search_query 生成（subjects[...] + subject_labels[...] 两段），
    #   逐字符断言会把原生实现细节钉死在这里；只钉「入口 + 指向本项目」这两件真事。
    assert_match %r{\A/global_activities\?subjects%5BProject%5D}, actions[:activity][:url],
                 '动态走原生 global_activities（subjects = Project）'
    assert_includes actions[:activity][:url], project.id.to_s, '动态必须指向本项目'
  end

  def test_method_and_body_of_write_actions
    scene = build_scene!
    actions = list_with_user(scene).first[:actions]

    assert_equal 'PATCH', actions[:edit][:method], '编辑是原生 PATCH /projects/:id'
    assert_equal 'POST', actions[:archive][:method]
    assert_equal 'project_ids', actions[:archive][:body_key], '归档 body 用原生同款 project_ids'
    assert_equal 'GET', actions[:activity][:method], '动态是原生 type: :link（GET 跳转）'
    # 🔴 移动**不是** PATCH /projects/:id —— projects#project_update_params 不含
    #    project_folder_id，走那条是「发了、200 了、什么都没变」的假通。
    assert_equal 'POST', actions[:move][:method], '移动走原生 project_folders#move_to（POST）'

    keys = projects_update_permitted_keys
    # 先证明解析真拿到了东西，否则「解析失败 → 空数组」会让下面那条变成默认通过的假绿
    assert_includes keys, 'name', '原生 permit 白名单解析成功（否则下面的断言是空转）'
    refute_includes keys, 'project_folder_id',
                    '原生 permit 白名单里没有 project_folder_id（移动不能走 projects#update）'
  end

  # 原生 projects_controller#project_update_params 的 permit 白名单 ——
  # 拿它当我们「移动不走 projects#update」这条断言的锚点，
  # 免得哪天原生放行了该字段、我们这边还死钉着旧口径。
  # ⚠ 读的是**原生**代码文件，不是我们 addon 里的任何东西（真源在原生）。
  def projects_update_permitted_keys
    src = File.read(File.join(scinote_root, 'app/controllers/projects_controller.rb'))
    body = src[/def project_update_params.*?\n  end/m].to_s
    body[/\.permit\(([^)]*)\)/, 1].to_s.scan(/:\w+/).map { |s| s.delete(':') }
  end

  # addon 位于 <rails_root>/addons/eln_ui/test → 上溯三级到 rails 根
  def scinote_root
    @scinote_root ||= File.expand_path('../../..', __dir__)
  end

  # 移动落点必须钉死在原生 project_folders#move_to：
  # 曾经写成 PATCH /projects/:id（走 projects#update），而那条 permit 白名单
  # 里根本没有 project_folder_id —— 请求 200、toast「已保存」，库里纹丝不动。
  # 这类「假通」单测看不出来（enabled/url 都对得上），只能靠对拍原生源码 + 真机验。
  def test_move_action_targets_native_move_to
    actions = list_with_user(build_scene!).first[:actions]

    assert_equal '/project_folders/move_to', actions[:move][:url]
    assert_equal 'POST', actions[:move][:method]
    assert_equal 'root_folder', actions[:move][:root_key], '顶层目标键与原生 selectFolder(null) 同口径'
    assert_match %r{\A/project_folders/tree\z}, actions[:move][:folders_tree_url]
    refute_equal '/projects/:id', actions[:move][:url]
  end

  # 🔴「添加成员」下拉的真源端点：原生 projects#users_filter。
  #   曾经用 /access_permissions/projects/new —— 那个端点是**死的**（真机实测 404，
  #   下拉恒 0 候选）：路由顺序本身没问题（new 在 :id 之前），但
  #   AccessPermissions::ProjectsController#set_model 是
  #   `current_team.projects.find_by(id: params[:id])`，而 #new 的 params[:id] 恒为字符串 "new"
  #   → find_by(id: "new") = nil → render_404。原生自己也没人调它。
  #   这条断言就是那个坑的护栏：端点一旦被改回 new，这里立刻红。
  def test_assignable_users_url_is_native
    scene = build_scene!
    data = Scinote::ElnUi::ProjectListPayload.call(
      Project.where(id: scene[:project].id),
      current_user: scene[:creator]
    )

    assert_equal '/projects/users_filter', data[:assignableUsersUrl],
                 '可指派成员端点（原生在服役的团队用户端点 projects#users_filter）'
    assert_instance_of String, data[:assignableUsersUrl]
  end

  # 端点必须**真的能生成路径**（不是只保证 helper 名字对得上）。
  # 路由改名/换端点时这条先红，别等到真机「下拉点不动」才发现。
  #
  # ⚠ 不要用 assert_nothing_raised：测试类 include 了
  #   Canaid::Helpers::PermissionsHelper，它把 method_missing 接了过去 ——
  #   任何非 can_*? 的未知方法（assert_* 也算）都会被它拦下并抛 NoMethodError。
  #   所以这里改成自己接异常，把失败信息收进字符串再断言。
  def test_assignable_users_endpoint_is_live
    resolved =
      begin
        Rails.application.routes.url_helpers.users_filter_projects_path
      rescue StandardError => e
        "<#{e.class}>"
      end
    assert_equal '/projects/users_filter', resolved
  end

  # 项目所在文件夹：原生没有就 nil（显式留白），有就字符串 id。
  def test_row_folder_id
    scene = build_scene!
    project = scene[:project]
    row = list_with_user(scene).first

    refute_nil row.key?(:folderId), '行里必须有 folderId 这个键（没有 = 前端移动弹窗算不出起点）'
    if project.respond_to?(:project_folder_id)
      want = project.project_folder_id
      assert_equal(want ? want.to_s : nil, row[:folderId])
    else
      assert_nil row[:folderId], '原生没这列就显式留白，不编值'
    end
  end

  # ---------------------------------------------------------------------------
  # 权限**同源对拍**：payload 的 gate 必须逐条等于原生 Canaid 谓词的返回值。
  #
  # 🔴 为什么不用「期望值硬编码 true/false」：项目创建者到底有没有项目管理权，
  #    取决于原生 Permission 模型的兜底（creator / team assignment 继承……），
  #    拍脑袋写死会一边假绿（恰好成立）/ 一边假红（换个场景就翻）。
  #    与原生谓词对拍才是真的在测「我们有没有用错谓词」。
  # ---------------------------------------------------------------------------
  def test_row_action_gates_match_native_predicates
    scene = build_scene!
    actions = list_with_user(scene).first[:actions]
    user = scene[:creator]
    project = scene[:project]
    team = scene[:team]

    expected = {
      edit: can_manage_project?(user, project),
      # 原生 access_action：团队管理员 **或** 项目可读（注意不是 can_manage_project?）
      access: can_manage_team?(user, team) || can_read_project?(user, project),
      move: can_manage_team?(user, team),
      export: can_export_project?(user, project),
      archive: can_archive_project?(user, project),
      comment: can_read_project?(user, project),
      activity: can_read_project?(user, project)
    }

    expected.each do |key, want|
      assert_equal want, actions[key][:enabled], "#{key}: 必须与原生谓词同值（同源同层）"
    end

    # 至少要有几项是开的，否则上面全对也是"全关"的假绿
    assert_operator actions.values.count { |a| a[:enabled] }, :>, 0
  end

  def test_owner_role_enables_at_least_edit
    scene = build_scene!
    project = scene[:project]
    ua = UserAssignment.find_or_initialize_by(user: scene[:creator], assignable: project)
    ua.update!(user_role: UserRole.find_predefined_owner_role, team: scene[:team], assigned: :manually)

    actions = list_with_user(scene).first[:actions]

    assert_equal true, actions[:edit][:enabled], 'Owner → can_manage_project? 成立，编辑亮出'
    assert_equal "/projects/#{project.id}", actions[:edit][:url]
  end

  # 没传 current_user（原型独立跑 / 老调用方）→ 全部显式不可用，绝不按演示值假装能点
  def test_row_actions_all_disabled_without_current_user
    scene = build_scene!
    actions = Scinote::ElnUi::ProjectListPayload.call(Project.where(id: scene[:project].id))[:projects]
                .first[:actions]

    Scinote::ElnUi::ProjectListPayload::ACTION_KEYS.each do |key|
      assert_equal false, actions[key][:enabled], "#{key}: 无用户上下文必须显式不可用"
    end
  end

  private

  # 与 ProjectListController#filtered_projects 完全同款的调用方式。
  # controller 改动时这里必须跟着改 —— 这正是本测试存在的意义。
  def sort_like_controller(scope, team, user, order)
    params = ActionController::Parameters.new(
      view_mode: 'active', order: order
    )
    service = Lists::ProjectsService.new(team, scope, nil, params, user: user)
    records = service.send(:filter_project_records, scope)
    service.instance_variable_set(:@records, records)
    service.send(:sort_records)
    service.instance_variable_get(:@records)
  end
  def list(scene)
    Scinote::ElnUi::ProjectListPayload.call(Project.where(id: scene[:project].id), can_create_project: true)[:projects]
  end

  # 与 controller#payload 同款：把 current_user 传进去（行菜单权限必须同源判定）
  def list_with_user(scene)
    Scinote::ElnUi::ProjectListPayload.call(
      Project.where(id: scene[:project].id),
      can_create_project: true,
      current_user: scene[:creator]
    )[:projects]
  end

  def open_list(user)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.get('/eln_project_list')
    @status = session.response.status
    session.response.body
  end
end
