# frozen_string_literal: true

# ELN UI —— 通知中心端点（报告 §5 第 5 项 #4 挂账 · spec SCN-DASH-7）
#
# 覆盖：
#   1. GET  /eln_notifications         → 返回当前用户通知列表 + 未读计数，且每条派生跳转 URL
#   2. PATCH /eln_notifications/:id/read → 标记已读，未读计数随之下降
#   3. NotificationsPayload 直接验证 subject → URL 派生（MyModule / ResourceApplication / 兜底）
#
# 读的是 NotificationPublisher 写入的同一张原生 Notification 表，不造二开表。
require_relative 'test_helper'

class ElnUiNotificationsEndpointTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  def setup
    @scene   = build_scene!
    @team    = @scene[:team]
    @project = @scene[:project]
    @creator = @scene[:creator]
    @exp     = make_experiment!(project: @project, creator: @creator)
    @task    = make_task!(experiment: @exp, creator: @creator)
    @owner   = make_user!(name: '项目负责人')
    join_team!(@owner, @team)
    make_project_owner!(@project, user: @owner)
  end

  # ---------- 端点：列表 + 未读计数 + URL 派生 ----------
  def test_index_returns_unread_count_and_items_with_url
    Scinote::ElnUi::NotificationPublisher.notify(@owner, title: '任务关闭', message: '任务 X 关闭申请', subject: @task)

    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session.get '/eln_notifications', headers: { 'ACCEPT' => 'application/json' }
    assert_equal 200, session.response.status

    body = JSON.parse(session.response.body)
    assert_operator body['unread'], :>=, 1
    assert_operator body['items'].size, :>=, 1

    item = body['items'].find { |i| i['title'] == '任务关闭' }
    refute_nil item, '列表含刚才写入的通知'
    assert_equal false, item['read'], '新建通知默认未读'

    # 🔴 V1.25 修：原断言写的是 `"/experiments/#{exp}/eln_task_detail"`
    #   —— **少了 `/my_modules/:id`**，是一条真机必 404 的 URL。
    #   它被固化进用例后，套件长期是绿的，等于「用测试给 bug 盖章」。
    #   现在按宿主真路由形状断言：/experiments/:experiment_id/my_modules/:id/eln_task_detail
    assert_equal "/experiments/#{@task.experiment_id}/my_modules/#{@task.id}/eln_task_detail",
                 item['url'], 'MyModule 主题派生到任务详情路由（含 /my_modules/:id）'

    # 反向护栏：断言字符串不够 —— 这条 URL 必须**真能 match 到宿主路由**。
    #   旧 bug 的本质是「形状看着像、路由表里没有」，光比对字符串抓不住这类错。
    assert_routable item['url']
  end

  # ---------- 端点：标记已读 ----------
  def test_read_marks_read_and_lowers_unread
    rec = Scinote::ElnUi::NotificationPublisher.notify(@owner, title: '待办', message: '请审核', subject: @task)
    refute_nil rec

    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }

    session.patch "/eln_notifications/#{rec.id}/read"
    assert_equal 200, session.response.status
    assert_equal true, JSON.parse(session.response.body)['ok']

    rec.reload
    refute_nil rec.read_at, '标记已读后 read_at 被填充'

    session2 = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@owner, scope: :user) }
    session2.get '/eln_notifications', headers: { 'ACCEPT' => 'application/json' }
    body = JSON.parse(session2.response.body)
    assert_equal 0, body['unread'], '已读后未读计数为 0（仅这一条）'
    item = body['items'].find { |i| i['id'] == rec.id }
    assert_equal true, item['read']
  end

  # ---------- 服务：ResourceApplication 主题 → 申请详情路由 ----------
  def test_payload_derives_resource_application_url
    draft = Scinote::ElnUi::ResourceApplicationWorkflow.create_draft(
      user: @owner, team: @team, project_id: @project.id,
      kind: 'material', name: '试剂', qty: 2, unit_price: 100,
      repository_id: target_repository_id(team: @team, creator: @owner) # ADR-0030 D7 必填
    )
    app = Scinote::ElnUi::ResourceApplication.find_by(no: draft[:no])
    Scinote::ElnUi::NotificationPublisher.notify(@owner, title: '申请', message: '已提交', subject: app)

    out = Scinote::ElnUi::NotificationsPayload.call(user: @owner)
    item = out[:items].find { |i| i[:title] == '申请' }
    refute_nil item
    assert_equal "/eln_res_apply/#{app.no}", item[:url], 'ResourceApplication 主题派生到申请详情路由'

    # 🔴 V1.25 反向护栏：这条 URL 必须真能 match 到宿主路由。
    #   这一分支原来写的是 `eln_res_apply_path`，而宿主真名是
    #   `eln_res_apply_detail_path`（config/routes.rb:474-476）—— NoMethodError
    #   被方法级的 `rescue StandardError → FALLBACK_URL` 吞掉，
    #   于是**所有**资源申请通知都静默落到资源中心（用户视角就是「点不进去」）。
    #   这条护栏 + 已去掉的裸 rescue = 同类事故不可能再静默。
    assert_routable item[:url]
  end

  # ---------- 服务：无 subject → 资源中心兜底 ----------
  def test_payload_falls_back_when_no_subject
    Scinote::ElnUi::NotificationPublisher.notify(@owner, title: '系统', message: 'Token 余额预警')

    out = Scinote::ElnUi::NotificationsPayload.call(user: @owner)
    item = out[:items].find { |i| i[:title] == '系统' }
    refute_nil item
    assert_equal '/eln_res_center', item[:url], '无主题通知落到资源中心兜底'
  end

  private

  # 反向护栏：URL 必须**真能 match 到宿主路由表**。
  #   本项目踩过的坑：断言字符串「看着对」，但路由表里根本没有
  #   （notifications_payload 少了 `/my_modules/:id`）—— 测试却一直绿，
  #   因为那条错 URL 被写进了断言本身。真机点下去 404，用户才知道。
  #   所以除了比对字符串，还要过一遍真实路由识别。
  def assert_routable(url)
    Rails.application.routes.recognize_path(url.to_s.split('?').first, method: :get)
  rescue ActionController::RoutingError => e
    flunk "URL 匹配不到任何宿主路由：#{url}（#{e.message}）"
  end
end
