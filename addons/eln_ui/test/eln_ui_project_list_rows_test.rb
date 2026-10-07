# frozen_string_literal: true
#
# ELN UI —— 项目列表**行集合**（Scinote::ElnUi::ProjectListRows）与文件夹行契约（V1.32 / 票 #84）
#
# 本文件守的规格：
#   SCN-PROJ-LIST-7  文件夹行（并集 / 有筛选只出项目 / 层级下钻 / 文件夹专属菜单）
#   SCN-PROJ-LIST-8  ID 列取 `code`（`PR<id>` / `PF<id>`），与数字主键分离
#   SCN-PROJ-LIST-13 「用户处于文件夹层级时，分页须覆盖项目行 ∪ 文件夹行的总数」
#   SCN-DASH-8       工作台卡片数字 ≡ 落点页**项目行**条数（文件夹行不计入）
#
# 🔴 本文件里最重要的不是「行集合包含文件夹」，而是两条**对拍**用例：
#   · `test_row_set_matches_native_service_call_*` —— 我们复刻的那三个分支
#     必须与原生 `Lists::ProjectsService#call` 的行集合**逐项一致**。
#     原生哪天改了分支（比如把 folder_search 那条改成按层级收敛），这里立刻红。
#     没有这条，`ProjectListRows` 就只是"看着像原生"的第二份定义。
#   · `test_workbench_invariant_*` —— 引入并集后，卡片数字与落点页条数这条不变式
#     最容易被打断（把文件夹行也算进去），必须钉死。

require_relative 'test_helper'

class ElnUiProjectListRowsTest < AcTest::Base
  include Warden::Test::Helpers
  include Canaid::Helpers::PermissionsHelper

  # ===========================================================================
  # ① 行集合 = 项目行 ∪ 文件夹行（无任何筛选条件时）
  # ===========================================================================

  def test_rows_are_union_of_projects_and_folders_without_filters
    scene = build_scene!
    folder = make_project_folder!(team: scene[:team], name: '并集用的文件夹')

    res = row_set(scene)

    kinds = res.rows.map { |r| r.class.name }.tally
    assert_equal 1, kinds['ProjectFolder'], "无筛选时文件夹行必须出现（#{kinds.inspect}）"
    assert_equal 1, kinds['Project'], '项目行也在'
    assert_equal 1, res.project_count, 'projectCount 只数**项目行**（文件夹行不计）'
    assert_includes res.rows.map(&:id), folder.id, '文件夹行就是那个文件夹'
  end

  # ===========================================================================
  # ② 与原生 `Lists::ProjectsService#call` 对拍（同一批参数、同一批数据）
  #
  # ⚠ 为什么必须对拍而不是「我读原生源码觉得对」：
  #   分支里三处都是反直觉的（folder_search 不按层级收敛 / 有筛选只出项目 /
  #   快速搜索框不算筛选）。靠人读源码对齐，下一次有人"顺手优化"就会静默分叉。
  # ===========================================================================

  def test_row_set_matches_native_service_call_without_filters
    scene = build_scene!
    make_project_folder!(team: scene[:team], name: '对拍-顶层文件夹')
    assert_row_set_matches_native(scene, {})
  end

  def test_row_set_matches_native_service_call_with_filters
    scene = build_scene!
    folder = make_project_folder!(team: scene[:team], name: '对拍-筛选时用的文件夹')
    # 顶层项目：命中 query ⇒ 应出现
    scene[:project].update!(name: '对拍-顶层的项目')
    # 文件夹内的项目：命中 query 但在**下一层** ⇒ 顶层不出现
    p = make_project!(team: scene[:team], creator: scene[:creator])
    p.update!(project_folder_id: folder.id, name: '对拍-文件夹内的项目')

    res = row_set(scene, { filters: { query: '对拍' } })

    assert_empty res.rows.select { |r| r.instance_of?(ProjectFolder) }, '有筛选不出文件夹行'
    assert_includes res.rows.map(&:id), scene[:project].id, '顶层且命中 query 的项目行'
    # ⚠ 这条曾经被我写成「文件夹里的项目也该出现」——**那是错的**。
    #   原生 `:filtered` 分支是 `projects.where(project_folder: @current_folder)`，
    #   顶层时 @current_folder 为 nil ⇒ `project_folder_id IS NULL`，
    #   文件夹内部的项目在顶层**本来就不出现**（这是原生既有行为，复刻时不许"修正"）。
    refute_includes res.rows.map(&:id), p.id,
                    ':filtered = 「命中 query ∩ 当前层」，文件夹内的项目在顶层不出现'

    assert_row_set_matches_native(scene, { filters: { query: '对拍' } })
  end

  def test_row_set_matches_native_service_call_with_folder_search
    scene = build_scene!
    make_project_folder!(team: scene[:team], name: '对拍-folder_search')

    assert_row_set_matches_native(scene, { filters: { folder_search: 'true' } })
  end

  def test_row_set_matches_native_service_call_inside_folder
    scene = build_scene!
    folder = make_project_folder!(team: scene[:team], name: '对拍-当前层')
    child = make_project_folder!(team: scene[:team], name: '对拍-子层', parent: folder)
    p = make_project!(team: scene[:team], creator: scene[:creator])
    # ⚠ 名字里必须带 '对拍'：`filters[:query]` 是**按名字 / PR<id> / 描述**匹配的，
    #   项目名若是工厂默认的 "AC project <hex>"，下面第三条会 0 命中而"看着像分支错了"。
    p.update!(project_folder_id: folder.id, name: '对拍-层内项目')

    assert_row_set_matches_native(scene, {}, folder: folder)
    assert_row_set_matches_native(scene, { search: '对拍' }, folder: folder)
    assert_row_set_matches_native(scene, { filters: { query: '对拍' } }, folder: folder)
    assert_equal 1, ProjectFolder.where(parent_folder_id: folder.id).count,
                 '前提：子文件夹确实建在这一层（否则上面三条比对少了一类行）'
  end

  # ===========================================================================
  # ③ 有筛选条件 ⇒ 只渲染项目行（SCN-PROJ-LIST-7 第 3 条）
  #
  # ⚠ 必须挑一个**与文件夹毫无关系**的筛选条件（这里用日期区间）：
  #   用「文件名」当条件的话，文件夹不出现也可以解释成"名字不匹配"，
  #   那样这条用例等于没测到「有筛选就砍掉文件夹」这条规则。
  # ===========================================================================

  def test_any_filter_drops_folder_rows_even_when_unrelated
    scene = build_scene!
    make_project_folder!(team: scene[:team], name: '筛选时不应出现的文件夹')
    # ⚠ `start_date_from` 过滤的是 `projects.start_date`（projects_service.rb:95），
    #   该列为 **NULL** 的项目不进区间（SQL 三值逻辑）——不设它，下面那条
    #   「前提：不该把项目也筛空」就会因为一个与文件夹无关的原因变红。
    scene[:project].update!(start_date: Date.new(2024, 1, 1))

    res = row_set(scene, { filters: { start_date_from: '2000-01-01' } })

    assert_empty res.rows.select { |r| r.instance_of?(ProjectFolder) },
                 '有任一筛选条件时**不得**渲染文件夹行（原生既有行为，复刻时不许"修正"）'
    assert_operator res.rows.size, :>, 0, '前提：这个筛选条件本身不该把项目也筛空'
  end

  # folder_search 同样只出项目行；且它的语义是"翻进所有文件夹里找"，
  # 所以**当前层级之外**的项目也要出现（这是它与其它筛选条件最容易写错的区别）。
  def test_folder_search_shows_projects_outside_current_folder
    scene = build_scene!
    outer = make_project_folder!(team: scene[:team], name: '外层')
    inner = make_project_folder!(team: scene[:team], name: '内层', parent: outer)
    deep = make_project!(team: scene[:team], creator: scene[:creator])
    deep.update!(project_folder_id: inner.id, name: 'ZZ-深处项目')

    res = row_set(scene, { filters: { folder_search: 'true' } }, folder: outer)

    assert_includes res.rows.map(&:id), deep.id,
                    'folder_search 必须跨层（不按当前文件夹收敛）—— 收敛了就会漏项目'
    assert_empty res.rows.select { |r| r.instance_of?(ProjectFolder) }, 'folder_search 只出项目行'
  end

  # 快速搜索框（params[:search]）**不算**「筛选条件」：文件夹行仍在，
  # 只是被按名称 / `PF<id>` 过滤过一遍（原生原名行为）。
  def test_quick_search_keeps_folder_rows_but_filters_by_name
    scene = build_scene!
    make_project_folder!(team: scene[:team], name: '搜索命中-甲')
    make_project_folder!(team: scene[:team], name: '别的名字')

    res = row_set(scene, { search: '搜索命中' })

    folders = res.rows.select { |r| r.instance_of?(ProjectFolder) }
    assert_equal ['搜索命中-甲'], folders.map(&:name),
                 '快速搜索框下文件夹行**仍然渲染**，并按名称收敛 —— 别把它并进 filters'
  end

  # ===========================================================================
  # ④ SCN-PROJ-LIST-8：ID 列取 `code`，与数字主键分离
  # ===========================================================================

  def test_project_row_has_pr_code_and_numeric_id
    scene = build_scene!
    row = http_payload(scene[:creator])['projects'].find { |r| !r['folder'] }

    assert_equal "PR#{scene[:project].id}", row['code'], 'code = PrefixedIdModel#code = PR<id>'
    assert_equal scene[:project].id.to_s, row['id'],
                 'id 仍是数字主键字符串 —— code 与 id 是两个独立字段，不得互换'
    refute_equal row['code'], row['id'], 'code 不得等于 id（否则就是没做这条）'
    assert_equal false, row['folder'], '项目行必须显式带 folder: false（行类型判别字段）'
  end

  def test_folder_row_has_pf_code_and_counts
    scene = build_scene!
    folder = make_project_folder!(team: scene[:team], name: '带计数的文件夹')
    inside = make_project!(team: scene[:team], creator: scene[:creator])
    inside.update!(project_folder_id: folder.id)
    make_project_folder!(team: scene[:team], name: '子文件夹', parent: folder)

    # ⚠ 计数文案走 I18n，**跟随请求 locale**（测试环境默认 :en，生产按用户语言）。
    #   这里显式切 zh-CN：宿主 zh-CN.yml 缺这个键 + 生产开了 fallbacks（zh-CN→en），
    #   不补 addon 自己的那份就会在中文界面上显示英文（见 addons/eln_ui/config/locales/zh-CN.yml）。
    #
    # 🔴🔴 切换方式只能用 `with_request_locale`（改 `I18n.default_locale`），
    #   **不能**用 `I18n.with_locale(:'zh-CN') { http_payload(...) }`：
    #   实测请求周期会把 `I18n.locale` 重置回 `default_locale`
    #   （探针：块内 `I18n.locale=:"zh-CN"`、块内直接 `I18n.t` 出中文，
    #    但请求里出来的仍是英文，请求结束后 `I18n.locale` 已变回 `:en`）。
    #   于是"看着写法没错、断言却总差一个语言"，很容易被误判成 addon 的 locale 没加载。
    row = with_request_locale(:'zh-CN') do
      http_payload(scene[:creator])['projects'].find { |r| r['folder'] }
    end

    assert_equal "PF#{folder.id}", row['code'], '文件夹行 ID 列 = PF<id>'
    assert_equal folder.id.to_s, row['id'], 'id 仍是数字主键'
    assert_equal true, row['folder']
    assert_equal '1 个项目 | 1 个文件夹', row['folderInfo'],
                 '计数文案 = 「x 个项目 | y 个文件夹」（中文，zh-CN 缺键由 addon 补）'
    refute_nil row['drillUrl'], '文件夹行必须带进入层级的下钻落点'
  end

  # ===========================================================================
  # ⑤ SCN-PROJ-LIST-13：分页覆盖「项目行 ∪ 文件夹行」的总数
  #    同时钉死：projectCount（页头「共 N 个项目」）**不含**文件夹行
  # ===========================================================================

  def test_pagination_total_covers_union_but_project_count_does_not
    scene = build_scene!
    2.times { |i| make_project_folder!(team: scene[:team], name: "分页文件夹#{i}") }

    res = http_payload(scene[:creator], per_page: '0')
    folders = res['projects'].count { |r| r['folder'] }
    projects = res['projects'].count { |r| !r['folder'] }

    assert_equal 2, folders, '前提：两个文件夹行都在'
    assert_equal projects + folders, res['pagination']['totalEntries'],
                 '分页总数覆盖并集（SCN-PROJ-LIST-13 的文件夹层级条款）'
    assert_equal projects, res['projectCount'],
                 'projectCount 只数项目行 —— 页头「共 N 个项目」不得把文件夹算进去'
  end

  # ===========================================================================
  # ⑥ SCN-DASH-8 不变式（引入并集后最容易被打破的一条）
  #
  # 工作台「参与项目」卡片数字 → 落点页 `?filters[members][]=<me>`。
  # 有筛选 ⇒ 只出项目行 ⇒ 数字必须逐位相等。
  # ===========================================================================

  def test_workbench_invariant_participated_count_equals_landing_project_rows
    scene = build_scene!
    # 造一个"我参与"的项目（Project 级 UA → 我的预定义角色）
    2.times do |i|
      p = make_project!(team: scene[:team], creator: scene[:creator])
      p.update!(name: "参与项目#{i}")
      ua = UserAssignment.find_or_initialize_by(user: scene[:creator], assignable: p)
      ua.update!(user_role: UserRole.find_predefined_normal_user_role,
                 team: scene[:team], assigned: :manually)
    end
    # 再造几个文件夹 + 别人参与的项目，证明**文件夹行不会混进这个数字**
    2.times { |i| make_project_folder!(team: scene[:team], name: "不变式文件夹#{i}") }

    card = Scinote::ElnUi::ProjectListScope.participation(
      team: scene[:team], user: scene[:creator], view_mode: 'active'
    )[:participated]

    res = http_payload(scene[:creator], filters: { members: [scene[:creator].id] })

    assert_operator card, :>, 0, '前提：卡片数字不能是 0（否则下面 0 == 0 是假绿）'
    assert_equal card, res['projectCount'],
                 '工作台卡片数字 ≡ 落点页**项目行**条数（SCN-DASH-8）'
    assert_equal card, res['pagination']['totalEntries'],
                 '落点页有筛选 ⇒ 只剩项目行 ⇒ 分页总数也必须等于卡片数字'
  end

  # ===========================================================================
  # ⑦ 文件夹层级下钻（SCN-PROJ-LIST-7 第 4 条）
  # ===========================================================================

  def test_folder_drill_scopes_rows_and_exposes_back_link
    scene = build_scene!
    folder = make_project_folder!(team: scene[:team], name: '下钻目标')
    child = make_project_folder!(team: scene[:team], name: '下钻-子文件夹', parent: folder)
    inside = make_project!(team: scene[:team], creator: scene[:creator])
    inside.update!(project_folder_id: folder.id, name: '下钻-层内项目')
    top = make_project!(team: scene[:team], creator: scene[:creator])
    top.update!(name: '下钻-顶层项目')

    res = http_payload(scene[:creator], project_folder_id: folder.id)

    ids = res['projects'].map { |r| r['id'] }
    assert_includes ids, inside.id.to_s, '当前层的项目行要在'
    assert_includes ids, child.id.to_s, '当前层的子文件夹行要在'
    refute_includes ids, top.id.to_s, '顶层项目不得出现在文件夹层级里'
    refute_includes ids, folder.id.to_s, '当前文件夹自己不作为行出现'

    nav = res['folderNav']
    assert_equal folder.id.to_s, nav['current']['id']
    assert_equal 'PF' + folder.id.to_s, nav['current']['code']
    assert_equal [folder.id.to_s], nav['trail'].map { |c| c['id'] }, 'trail（根→当前）里只有当前这一层'
    assert_equal '/eln_project_list', nav['upUrl'], '在根文件夹里 ⇒ 返回上一层 = 顶层列表'
  end

  def test_folder_drill_trail_is_root_first
    scene = build_scene!
    a = make_project_folder!(team: scene[:team], name: '甲级')
    b = make_project_folder!(team: scene[:team], name: '乙级', parent: a)
    c = make_project_folder!(team: scene[:team], name: '丙级', parent: b)

    res = http_payload(scene[:creator], project_folder_id: c.id)

    assert_equal [a.id.to_s, b.id.to_s, c.id.to_s], res['folderNav']['trail'].map { |x| x['id'] },
                 '面包屑必须**根在前**（原生 parent_folders 的 ORDER BY 不保证这个顺序，我们逐级回溯）'
    assert_equal "/eln_project_list?project_folder_id=#{b.id}", res['folderNav']['upUrl'],
                 '「返回上一层」落到父级（不是一路回顶层）'
  end

  # 手改 URL 的容错：不存在的 id / 别的团队的 id 都不能炸，也不能泄漏。
  def test_unknown_or_foreign_folder_id_falls_back_to_top_level
    scene = build_scene!
    other = build_scene!
    foreign = make_project_folder!(team: other[:team], name: '别人的文件夹')

    [999_999_999, foreign.id].each do |bad|
      res = http_payload(scene[:creator], project_folder_id: bad)

      assert_nil res['folderNav']['current'],
                 "非法/越权 project_folder_id=#{bad} 必须退回顶层（不 404、不 500、不泄漏）"
      assert_nil res['folderNav']['upUrl'],
                 '顶层没有"上一层" ⇒ upUrl 为 nil，前端据此**不渲染**面包屑（不是渲染死入口）'
      assert_operator res['projects'].size, :>, 0, '退回顶层后仍要正常出数据（不是空页）'
    end
  end

  # ===========================================================================
  # ⑧ 文件夹行菜单：**专属集合**且 gate 与原生谓词同源
  # ===========================================================================

  def test_folder_actions_are_folder_specific
    scene = build_scene!
    folder = make_project_folder!(team: scene[:team], name: '菜单用的空文件夹')
    row = http_payload(scene[:creator])['projects'].find { |r| r['folder'] }
    acts = row['actions']

    assert_equal %w[delete edit move], acts.keys.sort, '只有文件夹专属三项'
    Scinote::ElnUi::ProjectListPayload::ACTION_KEYS.each do |forbidden|
      next if %i[edit move].include?(forbidden)

      refute acts.key?(forbidden.to_s),
             "文件夹行**不得**出现项目专属动作 #{forbidden}（SCN-PROJ-LIST-7 第 6 条）"
    end
    assert_equal 'PATCH', acts['edit']['method']
    assert_equal "/project_folders/#{folder.id}", acts['edit']['url']
    assert_equal '/project_folders/move_to', acts['move']['url']
    assert_equal '/project_folders/destroy', acts['delete']['url']
    assert_equal 'project_folder_ids', acts['delete']['body_key'],
                 '删除端点收的是 project_folder_ids（不是 project_ids —— 发错键会静默 0 删除）'
  end

  # gate 与原生谓词**逐条对拍**（硬编码 true/false 会假绿/假红，见 list 测试里同款理由）
  def test_folder_action_gates_match_native_predicates
    scene = build_scene!
    folder = make_project_folder!(team: scene[:team], name: 'gate 对拍')
    ua = UserAssignment.find_by(assignable_type: 'Team', assignable_id: scene[:team].id,
                                user_id: scene[:creator].id)
    ua.update!(user_role: UserRole.find_predefined_owner_role, assigned: :manually)
    user = scene[:creator]
    team = scene[:team]

    acts = http_payload(user)['projects'].find { |r| r['folder'] }['actions']

    assert_equal can_create_project_folders?(user, team), acts['edit']['enabled'],
                 'edit 的 gate = can_create_project_folders?（原生 edit_action 的 else 支）'
    assert_equal can_manage_team?(user, team), acts['move']['enabled'], 'move = can_manage_team?'
    assert_equal can_delete_project_folder?(user, folder), acts['delete']['enabled'],
                 'delete = can_delete_project_folder?（自带「文件夹必须为空」条件）'
    assert_equal true, acts['edit']['enabled'], '前提：Owner 应当开得了编辑（否则上面是"全关"假绿）'
  end

  # 非空文件夹删不掉（原生谓词的 `projects.none? && project_folders.none?`）——
  # 该项必须**不亮**，而不是亮着再让服务端 422。
  def test_non_empty_folder_delete_is_not_enabled
    scene = build_scene!
    folder = make_project_folder!(team: scene[:team], name: '非空文件夹')
    p = make_project!(team: scene[:team], creator: scene[:creator])
    p.update!(project_folder_id: folder.id)
    ua = UserAssignment.find_by(assignable_type: 'Team', assignable_id: scene[:team].id,
                                user_id: scene[:creator].id)
    ua.update!(user_role: UserRole.find_predefined_owner_role, assigned: :manually)

    acts = http_payload(scene[:creator])['projects'].find { |r| r['folder'] }['actions']

    assert_equal false, acts['delete']['enabled'], '非空文件夹：删除项不亮（原生同此，不靠服务端兜）'
    assert_equal true, acts['move']['enabled'], '前提：同一个文件夹的移动是亮的（否则"全关"假绿）'
  end

  def test_folder_actions_all_disabled_without_current_user
    scene = build_scene!
    make_project_folder!(team: scene[:team], name: '无用户上下文')

    acts = Scinote::ElnUi::ProjectListPayload.call(
      ProjectFolder.where(team_id: scene[:team].id)
    )[:projects].first[:actions]

    Scinote::ElnUi::ProjectListPayload::FOLDER_ACTION_KEYS.each do |key|
      assert_equal false, acts[key][:enabled], "#{key}: 无 current_user 必须显式不可用"
    end
  end

  # ===========================================================================
  # ⑨ 行集合不得把文件夹算进项目统计（regression：stats_index 按 project.id 建索引）
  # ===========================================================================

  def test_folder_row_does_not_receive_project_stats
    scene = build_scene!
    make_project_folder!(team: scene[:team], name: '统计隔离')

    row = http_payload(scene[:creator])['projects'].find { |r| r['folder'] }

    assert_equal 0, row['total'], '文件夹行不得借用某个项目的实验数'
    assert_equal 0, row['commentsCount']
    assert_equal [], row['members']
    assert_nil row['status'], '文件夹没有状态（不假装成"进行中"）'
  end

  private

  # ------------------------------------------------------------------
  # 与 controller#row_set 完全同款的调用方式。
  # controller 改动时这里必须跟着改 —— 这正是本测试存在的意义。
  # ------------------------------------------------------------------
  def row_set(scene, params_hash = {}, folder: nil)
    params = ActionController::Parameters.new({ view_mode: 'active' }.merge(params_hash))
    Scinote::ElnUi::ProjectListRows.call(
      team: scene[:team],
      user: scene[:creator],
      view_mode: 'active',
      params: params,
      scope: Scinote::ElnUi::ProjectListScope
        .for_listing(team: scene[:team], user: scene[:creator], view_mode: 'active')
        .order(name: :asc),
      current_folder: folder
    )
  end

  # 🔴 对拍：同一批数据、同一批参数，原生 `call` 与 `ProjectListRows` 的行集合必须逐项一致。
  #
  # ⚠ per_page 给一个大值：原生 `call` 末段是 Kaminari 分页（`Array#page/per` 不传时默认 25），
  #   被截断的比对等于没比对。`page`/`per_page` 只在原生侧有意义，不进 RowS 的分支判断。
  def assert_row_set_matches_native(scene, params_hash, folder: nil)
    # ⚠ 原生 `fetch_projects` 第一行就是 `MyModuleStatusFlow.first.final_status.id`
    #   （projects_service.rb:41）—— 测试库里没有流程时它会 NoMethodError on nil，
    #   于是"对拍"变成"跑不起来"。`ensure_default` 是宿主自带的幂等入口（生产也在用），
    #   调它比自己拼一条流程更不容易踩 Extends 常量。
    MyModuleStatusFlow.ensure_default
    params_hash = { view_mode: 'active' }.merge(params_hash)
    scope = Scinote::ElnUi::ProjectListScope
            .for_listing(team: scene[:team], user: scene[:creator], view_mode: 'active')
            .order(name: :asc)

    native = Lists::ProjectsService
             .new(scene[:team], scope, folder,
                  ActionController::Parameters.new(params_hash.merge(page: '1', per_page: '1000')),
                  user: scene[:creator])
             .call
    native_keys = native.map { |r| [r.class.name, r.id] }

    ours = row_set(scene, params_hash, folder: folder).rows.map { |r| [r.class.name, r.id] }

    assert_equal native_keys, ours,
                 "行集合必须与原生 Lists::ProjectsService#call 逐项一致（params=#{params_hash.inspect}, " \
                 "folder=#{folder&.id.inspect}）—— 分叉说明 ProjectListRows 的分支复刻走样了"
    assert_operator native_keys.size, :>, 0, '前提：这次比对不能是"两边都空"（那是假绿）'
  end

  # json 出口（走真 HTTP，覆盖 controller → payload 的整条链）
  def http_payload(user, params = {})
    s = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    s.get('/eln_project_list', params: params.merge(format: :json))
    assert_equal 200, s.response.status, "json 出口必须 200（params=#{params.inspect}）"
    JSON.parse(s.response.body)
  end

  # 🔴 让**请求里**用指定语言渲染的唯一可靠办法：改 `I18n.default_locale`。
  #
  #   为什么不是 `I18n.with_locale`：
  #     请求周期（Rails 7.2 的 executor/reloader）会把 `I18n.locale` 复位成 default，
  #     所以 `I18n.with_locale(:'zh-CN') { session.get(...) }` 里的那份线程 locale
  #     在 controller 里**已经消失**（块内直接 `I18n.t` 是中文，请求里出来的却是英文）。
  #     症状：断言恒差一个语言，但 `I18n.t` 单测又过 ⇒ 极易误判成"addon 的 locale 没加载"。
  #   这是本项目第 N 次 i18n 假绿，写法收在这里，别在别处再写一遍 with_locale。
  def with_request_locale(locale)
    old = ::I18n.default_locale
    ::I18n.default_locale = locale
    yield
  ensure
    ::I18n.default_locale = old
  end

  # ⚠ ProjectFolder 没有 created_by 列（模型里只有 team / parent_folder / archived_by），
  #   所以工厂只给 name + team + parent。名字长度要过 Constants::NAME_MIN_LENGTH。
  def make_project_folder!(team:, name:, parent: nil)
    ProjectFolder.create!(name: name, team: team, parent_folder: parent)
  end
end
