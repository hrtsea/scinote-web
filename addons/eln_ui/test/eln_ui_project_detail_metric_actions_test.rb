# frozen_string_literal: true
#
# ELN UI —— 项目指标 CRUD + 达标切换（2026-10-11 起）
#
# 承载面 = 二开表 eln_ui_project_metrics（原生 projects 无项目级指标模型，
# 这是「原生无承载面 → addon 自有表」纪律的又一处落地，与文档/任务审核同源）。
# 四条动作共用 canEditBasic 闸门（与「编辑项目信息」同款权限，不另立权限档）。
# 创建即未达标（ok 默认 false），达标只走「切换达标」动作，不进创建/编辑表单。
#
# 对拍铁律：把四条动作的 `return render_403 unless current_permissions[:canEditBasic]`
# 摘掉 → 受限成员（role: :restricted，看得见项目、不可编辑）的 403 用例必须精确变红。

require_relative 'test_helper'

# 本地（非 docker）环境 Warden 不会自动 autoload；docker/CI 里由宿主装配。
# 仅为让本机可跑测试，warden 本就是依赖，不影响 CI。
begin
  require 'warden'
  require 'warden/test/helpers'
rescue LoadError
  nil
end

class ElnUiProjectDetailMetricActionsTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  # ------------------------------------------------------------
  # 权限闸门：受限成员四条动作全部 403（可见项目、不可编辑）
  # ------------------------------------------------------------

  def test_restricted_member_cannot_create_metric
    scene = build_scene!
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :restricted, name: 'restricted1')

    status, = post_metric(member, scene[:project], metric: { name: 'X', target: 'Y', current: 'Z' })

    assert_equal 403, status
  end

  def test_restricted_member_cannot_update_metric
    scene = build_scene!
    m = Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: 'M', position: 1)
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :restricted, name: 'restricted2')

    status, = patch_metric(member, scene[:project], m.id, metric: { name: 'M2' })

    assert_equal 403, status
  end

  def test_restricted_member_cannot_destroy_metric
    scene = build_scene!
    m = Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: 'M', position: 1)
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :restricted, name: 'restricted3')

    status, = delete_metric(member, scene[:project], m.id)

    assert_equal 403, status
  end

  def test_restricted_member_cannot_toggle_metric
    scene = build_scene!
    m = Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: 'M', position: 1, ok: false)
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :restricted, name: 'restricted4')

    status, = toggle_metric(member, scene[:project], m.id)

    assert_equal 403, status
  end

  # ------------------------------------------------------------
  # 创建：成功 + 返回体带 id 与 per-row 动作端点 + 真库落盘
  # ------------------------------------------------------------

  def test_owner_can_create_metric_pending_by_default
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    status, body = post_metric(scene[:creator], scene[:project],
                               metric: { name: '拉伸剪切强度', target: '≥ 8.0 MPa', current: '7.4 MPa' })

    assert_equal 200, status
    metrics = body['projectMetrics']
    assert_equal 1, metrics.size
    assert_equal '拉伸剪切强度', metrics.first['name']
    refute metrics.first['ok'], '创建即未达标'
    # 返回体必须带 id 与 per-row 动作端点（前端不许拼宿主路径）
    id = metrics.first['id']
    assert id.present?
    assert_equal "/projects/#{scene[:project].id}/eln_project_detail/metrics/#{id}",
                 metrics.first.dig('actions', 'update')
    assert_equal "/projects/#{scene[:project].id}/eln_project_detail/metrics/#{id}",
                 metrics.first.dig('actions', 'destroy')
    assert_equal "/projects/#{scene[:project].id}/eln_project_detail/metrics/#{id}/toggle",
                 metrics.first.dig('actions', 'toggle')
    assert_equal "/projects/#{scene[:project].id}/eln_project_detail/metrics",
                 body.dig('actions', 'addMetric')
    # 真库落了
    assert_equal 1, Scinote::ElnUi::ProjectMetric.where(project_id: scene[:project].id).count
  end

  def test_create_rejects_blank_name
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    status, body = post_metric(scene[:creator], scene[:project], metric: { name: '', target: 'Y', current: 'Z' })

    assert_equal 422, status
    assert_includes body['error'].to_s, '名称'
    assert_equal 0, Scinote::ElnUi::ProjectMetric.where(project_id: scene[:project].id).count, '失败的写入不留副作用'
  end

  # ------------------------------------------------------------
  # 更新
  # ------------------------------------------------------------

  def test_owner_can_update_metric
    scene = build_scene!
    m = Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: 'M', target: 't', current: 'c', position: 1)
    make_project_owner!(scene[:project], user: scene[:creator])

    status, = patch_metric(scene[:creator], scene[:project], m.id, metric: { name: 'M2', target: 't2', current: 'c2' })

    assert_equal 200, status
    m.reload
    assert_equal 'M2', m.name
    assert_equal 't2', m.target
    assert_equal 'c2', m.current
  end

  # ------------------------------------------------------------
  # 删除
  # ------------------------------------------------------------

  def test_owner_can_destroy_metric
    scene = build_scene!
    m = Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: 'M', position: 1)
    make_project_owner!(scene[:project], user: scene[:creator])

    status, = delete_metric(scene[:creator], scene[:project], m.id)

    assert_equal 200, status
    assert_equal 0, Scinote::ElnUi::ProjectMetric.where(project_id: scene[:project].id).count
  end

  # ------------------------------------------------------------
  # 达标切换：翻转 ok
  # ------------------------------------------------------------

  def test_owner_can_toggle_metric_ok
    scene = build_scene!
    m = Scinote::ElnUi::ProjectMetric.create!(project_id: scene[:project].id, name: 'M', position: 1, ok: false)
    make_project_owner!(scene[:project], user: scene[:creator])

    status, body = toggle_metric(scene[:creator], scene[:project], m.id)

    assert_equal 200, status
    toggled = body['projectMetrics'].find { |x| x['id'] == m.id }
    assert toggled['ok'], '切换后达标'
    assert m.reload.ok, '真库 ok 翻转'
  end

  private

  def post_metric(user, project, params)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.post "/projects/#{project.id}/eln_project_detail/metrics",
                 params: params.to_json,
                 headers: { 'CONTENT_TYPE' => 'application/json' }
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end

  def patch_metric(user, project, id, params)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.patch "/projects/#{project.id}/eln_project_detail/metrics/#{id}",
                  params: params.to_json,
                  headers: { 'CONTENT_TYPE' => 'application/json' }
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end

  def delete_metric(user, project, id)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.delete "/projects/#{project.id}/eln_project_detail/metrics/#{id}",
                   headers: { 'CONTENT_TYPE' => 'application/json' }
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end

  def toggle_metric(user, project, id)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.post "/projects/#{project.id}/eln_project_detail/metrics/#{id}/toggle",
                 headers: { 'CONTENT_TYPE' => 'application/json' }
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end
end
