# frozen_string_literal: true
#
# ELN UI —— 项目详情页「服务端网格」端点（scinote/eln_ui/project_detail#grid）
#
# 2026-10-11 新增。为什么需要这个端点：本页 6 张表从「payload 内联渲染」改为宿主
# shared/datatable（AG Grid v32.3.9），而宿主栈**只能**从 dataUrl 拉数据
# （`dataUrl` 是它的 required prop）⇒ 需要一个服务端取数口。做法与资源中心
# （res_center#grid）、项目列表（eln_project_list#grid）同源。
#
# 这条测试守两件事（都不许靠「读一遍实现再抄断言」）：
#   1. **契约形状**：{ data: [{id, type, attributes}], meta: {total_pages, total_count,
#      filtered_count} }。宿主 `formatData` 会把 attributes 摊平成行对象 ⇒
#      前端 columnDefs.field 必须 == attributes 的键；id/type 是宿主 getRowId 与
#      行选择逻辑的依赖，缺了会静默拿到 undefined 行。
#   2. **单真源**：每个 dataset 的值必须来自真库 / 既有 block，不是端点里另写一套聚合。
#      所以断言一律写成「真库有什么 → 网格就该是什么」。
#
# 排序/分页口径由 Scinote::ElnUi::GridSupport 提供（与 ResCenter 共用一份实现），
# 它的行为由 eln_ui_res_center_test 的既有断言守着；这里只验证「本端点确实接上了它」。

require_relative 'test_helper'

# 本地（非 docker）环境 Warden 不会自动 autoload；docker/CI 里由宿主装配。
# 仅为让本机可跑测试 —— 缺这段会在 require 阶段直接抛 uninitialized constant Warden，
# 本文件内的用例**一个都不会被加载**（且全量 run 里只表现为总数变少，不报错）。
begin
  require 'warden'
  require 'warden/test/helpers'
rescue LoadError
  nil
end

class ElnUiProjectDetailGridTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  # ------------------------------------------------------------
  # 契约形状
  # ------------------------------------------------------------

  def test_contract_shape
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: 'M1', position: 1)

    status, body = get_grid(scene[:creator], scene[:project], dataset: 'metrics')

    assert_equal 200, status
    assert body.key?('data'), '必须给 data'
    assert body.key?('meta'), '必须给 meta（宿主分页条要读 total_pages/total_count）'

    row = body['data'].first
    assert row.key?('id'), '每行必须有 id —— 宿主 getRowId / 行选择逻辑依赖它'
    assert row.key?('type')
    assert row.key?('attributes'), 'attributes 会被宿主摊平成行字段'
    assert_equal %w[filtered_count total_count total_pages].sort, body['meta'].keys.sort
  end

  # ------------------------------------------------------------
  # metrics：值来自 eln_ui_project_metrics（既有 metrics_block 同一份取数）
  # ------------------------------------------------------------

  def test_metrics_dataset_reads_real_table
    scene = build_scene!
    Scinote::ElnUi::ProjectMetric.create!(
      project_id: scene[:project].id, name: '拉伸剪切强度',
      target: '≥ 8.0 MPa', current: '7.4 MPa', ok: true, position: 1
    )

    _status, body = get_grid(scene[:creator], scene[:project], dataset: 'metrics')

    attrs = body['data'].first['attributes']
    assert_equal '拉伸剪切强度', attrs['name'], '指标名必须来自真表'
    assert_equal '≥ 8.0 MPa', attrs['target']
    assert attrs['ok'], 'ok 来自真表（创建即未达标、达标只走 toggle）'
    assert attrs['actions'].present?, 'per-row 动作端点必须随行下发（前端不许拼宿主路径）'
    assert attrs['actions']['toggle'].to_s.end_with?('/toggle')
  end

  # 指标 CRUD 后网格要能反映真库（不是缓存/快照）
  def test_metrics_dataset_reflects_create
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    assert_empty get_grid(scene[:creator], scene[:project], dataset: 'metrics')[1]['data']

    Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: '新指标', position: 1)

    _status, body = get_grid(scene[:creator], scene[:project], dataset: 'metrics')
    assert_equal 1, body['data'].size
    assert_equal 1, body['meta']['total_count']
  end

  # ------------------------------------------------------------
  # members：值来自项目成员指派（既有 members_block 同一份取数）
  # ------------------------------------------------------------

  def test_members_dataset_reads_real_members
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    _status, body = get_grid(scene[:creator], scene[:project], dataset: 'members')

    assert_equal scene[:project].user_assignments.where(assignable_type: 'Project').count,
                 body['meta']['total_count'], '成员行数必须等于真库指派数'
    attrs = body['data'].first['attributes']
    assert attrs['name'].present?, '成员名必须来自真库用户'
    assert attrs.key?('title'), '业务称谓列走 ROLE_TITLES 映射'
    assert attrs.key?('color'), '头像配色由服务端按序轮转下发（前端不再自己算）'
  end

  # ------------------------------------------------------------
  # required_docs：uploaded 布尔必须来自真库（状态徽章据此上色）
  # ------------------------------------------------------------

  def test_required_docs_dataset_reads_real_documents
    scene = build_scene!
    task_book = Scinote::ElnUi::ProjectDocument.create!(
      project_id: scene[:project].id, category: 'required',
      name: '项目任务书', version: 2, uploaded: true
    )
    closing = Scinote::ElnUi::ProjectDocument.create!(
      project_id: scene[:project].id, category: 'required',
      name: '结题报告', uploaded: false
    )

    _status, body = get_grid(scene[:creator], scene[:project], dataset: 'required_docs')

    attrs = body['data'].first['attributes']
    assert_equal '项目任务书', attrs['name']
    assert attrs['uploaded'], 'uploaded 必须来自真表 —— 前端据此渲染「已上传/待上传」'
    # ADR-0049 D7：docs_block 下发 :id 后，grid 行 id = 台账主键（不再是 row-N 伪位）——
    # 前端 per-row 上传（T4）靠这个 id 回传定位。
    assert_equal [task_book.id.to_s, closing.id.to_s], body['data'].map { |r| r['id'] },
                 '网格行 id 必须等于台账主键（paginate 的 row-N 兜底不许生效）'
  end

  # ------------------------------------------------------------
  # 未知 dataset：空网格（而不是静默拿全量数据充数）
  # ------------------------------------------------------------

  def test_unknown_dataset_returns_empty_grid
    scene = build_scene!

    status, body = get_grid(scene[:creator], scene[:project], dataset: 'not_a_dataset')

    assert_equal 200, status
    assert_empty body['data'], '未知 dataset 必须是空表，不许兜底给别的表的数据'
    assert_equal 0, body['meta']['total_count']
  end

  # ------------------------------------------------------------
  # 服务端排序 / 分页：确认本端点真的接上了 GridSupport
  # ------------------------------------------------------------

  def test_server_side_sorting_by_name_desc
    scene = build_scene!
    %w[alpha bravo charlie].each_with_index do |n, i|
      Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: n, position: i + 1)
    end

    _status, body = get_grid(scene[:creator], scene[:project],
                             dataset: 'metrics', order: { column: 'name', dir: 'desc' })

    names = body['data'].map { |r| r['attributes']['name'] }
    assert_equal %w[charlie bravo alpha], names, '降序必须由服务端完成（客户端排序在宿主栈里被关掉）'
  end

  def test_server_side_pagination_slices_rows
    scene = build_scene!
    %w[one two three].each_with_index do |n, i|
      Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: n, position: i + 1)
    end

    _status, body = get_grid(scene[:creator], scene[:project],
                             dataset: 'metrics', per_page: 1, page: 2)

    assert_equal 1, body['data'].size, '第 2 页每页 1 条，应只切出 1 行'
    assert_equal 3, body['meta']['total_count'], 'total_count 是过滤后总数（不是本页行数）'
    assert_equal 3, body['meta']['total_pages']
  end

  # ------------------------------------------------------------
  # 端点 URL 由 payload 逐条下发（前端零拼接 —— paths 铁律）
  # ------------------------------------------------------------

  def test_payload_dispatches_all_seven_grid_urls
    scene = build_scene!
    payload = Scinote::ElnUi::ProjectDetailPayload.call(scene[:project])
    grids = payload[:actions][:grids]

    expected = %i[experiments metrics requiredDocs otherDocs members cost taskCloseReview]
    assert_equal expected.sort, grids.keys.sort, '6 张表（7 个 dataset）的 URL 必须齐备'

    grids.each do |key, url|
      assert_includes url, "/projects/#{scene[:project].id}/eln_project_detail/grid",
                      "#{key} 的 URL 必须指向本页网格端点"
      assert_includes url, 'dataset=', "#{key} 的 URL 必须自带 dataset（前端不许拼 query）"
    end
    # dataset 取值与 ProjectDetailPayload#grid_dataset_rows 的分支一一对应
    assert_includes grids[:metrics], 'dataset=metrics'
    assert_includes grids[:requiredDocs], 'dataset=required_docs'
    assert_includes grids[:taskCloseReview], 'dataset=task_close_review'
  end

  private

  def get_grid(user, project, params = {})
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.get("/projects/#{project.id}/eln_project_detail/grid", params: params)
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end
end
