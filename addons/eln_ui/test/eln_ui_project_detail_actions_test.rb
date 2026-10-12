# frozen_string_literal: true
#
# ELN UI —— 项目详情页**页头三键**的接线契约（2026-10-11）
#
# 背景：这三个按钮此前是纯静态标签（没有 @click、没有权限判断、没有端点），
#   点下去毫无反应。本文件守的是「接线之后**真的能改到库里**」以及
#   「**不该按的人按不动**」这两头 —— 少了前者是假接线，少了后者是发写入口给所有人。
#
# 对拍铁律：把权限门摘掉 → 这些用例必须精确变红。

require_relative 'test_helper'

class ElnUiProjectDetailActionsTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  # ------------------------------------------------------------
  # permissions：下发依据（前端据此决定渲染与否）
  # ------------------------------------------------------------

  def test_permissions_fail_closed_without_user
    scene = build_scene!

    perms = payload_permissions(scene[:project], nil)

    refute perms[:canEditBasic], '没有用户时必须 fail-closed'
    refute perms[:canUploadDocs], '没有用户时必须 fail-closed'
    refute perms[:canChangeStatus], '没有用户时必须 fail-closed'
  end

  def test_owner_can_edit_upload_and_archive
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    perms = payload_permissions(scene[:project], scene[:creator])

    assert perms[:canEditBasic], '项目负责人可编辑基础信息（SCN-PM-BASIC-1）'
    assert perms[:canUploadDocs], '项目负责人可上传文档（SCN-PM-BASIC-1）'
    assert perms[:canChangeStatus], '项目负责人可改状态（REQ-PM-ARCHIVE / SCN-PM-ARCH-1）'
  end

  # 「组员只读」这条最容易被漏：按钮一视同仁地渲染出来，等于把写入口发给所有人。
  def test_plain_member_cannot_archive
    scene = build_scene!
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :normal, name: 'pdmember')

    perms = payload_permissions(scene[:project], member)

    assert perms[:canEditBasic], '小组组长/成员可编辑基础信息（SCN-PM-BASIC-1）'
    refute perms[:canChangeStatus], '归档（置已结题）必须只归项目负责人'
  end

  # ------------------------------------------------------------
  # 二开三格（编号 / 来源 / 状态）真的有地方存、也真的被读出来
  # ------------------------------------------------------------

  def test_profile_fields_feed_basic_info
    scene = build_scene!
    Scinote::ElnUi::ProjectProfile.upsert_for!(
      scene[:project], business_code: 'ELN-PROJ-2026-018', source: '国家重点研发计划'
    )

    basic = payload(scene)[:projectBasic]

    assert_equal 'ELN-PROJ-2026-018', basic[:code], '有二开编号时用业务编号，不用主键'
    assert_equal '国家重点研发计划', basic[:source], '项目来源取自二开档案'
  end

  def test_without_profile_code_falls_back_to_primary_key
    scene = build_scene!

    basic = payload(scene)[:projectBasic]

    assert_equal "##{scene[:project].id}", basic[:code], '没有二开编号时回落系统主键'
    assert_nil basic[:source], '没有来源就留白，绝不编一个'
  end

  # ⚠ 这条守的是「页面显示已结题、原生却还能建任务」那种撕裂：
  #   展示态必须以原生 archived 为准，不听二开列。
  def test_archived_project_shows_closed_regardless_of_profile
    scene = build_scene!
    Scinote::ElnUi::ProjectProfile.upsert_for!(scene[:project], status: 'running')
    scene[:project].update!(archived: true)

    basic = payload(scene)[:projectBasic]

    assert_equal '已结题', basic[:status]
    assert_equal 'closed', basic[:statusKey], '前端按 statusKey 选配色，不拿中文文案做比较'
  end

  # ------------------------------------------------------------
  # actions：端点 URL 必须来自宿主 named route（不许前端手拼）
  # ------------------------------------------------------------

  def test_actions_use_host_routes_for_this_project
    scene = build_scene!
    pid = scene[:project].id

    acts = payload(scene)[:actions]

    assert_equal "/projects/#{pid}/eln_project_detail", acts[:updateProject]
    assert_equal "/projects/#{pid}/eln_project_detail/status", acts[:changeStatus]
    # ADR-0049 D8：原 uploadTaskBook（写死「项目任务书」）退役，改为行级 document 端点。
    assert_equal "/projects/#{pid}/eln_project_detail/document", acts[:uploadDocument]
  end

  # ------------------------------------------------------------
  # 端点：真的改到库里 / 不该按的人按不动
  # ------------------------------------------------------------

  def test_update_writes_native_and_profile_fields
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    status, = patch_project(scene[:creator], scene[:project],
                            project: { name: '改名后的项目', business_code: 'ELN-PROJ-2026-001' })

    assert_equal 200, status
    assert_equal '改名后的项目', scene[:project].reload.name, '原生列必须真被改'
    assert_equal 'ELN-PROJ-2026-001',
                 Scinote::ElnUi::ProjectProfile.find_by(project_id: scene[:project].id).business_code,
                 '二开编号必须落到 eln_ui_project_profiles'
  end

  # 立项时间 = 项目批准日期，必须能写进去，且**不能**落到 projects.created_at。
  def test_update_writes_approved_on
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    status, = patch_project(scene[:creator], scene[:project], project: { approved_on: '2026-03-02' })

    assert_equal 200, status
    assert_equal Date.new(2026, 3, 2),
                 Scinote::ElnUi::ProjectProfile.find_by(project_id: scene[:project].id).approved_on,
                 '立项（批准）日期必须落到二开档案'
    refute_equal scene[:project].reload.created_at.to_date, Date.new(2026, 3, 2),
                 'created_at 不得被当成立项时间改写'
  end

  def test_change_status_archives_the_project
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    status, = post_status(scene[:creator], scene[:project], status: 'closed')

    assert_equal 200, status
    assert scene[:project].reload.archived?, '置已结题必须落到原生 archived（禁建任务靠它）'
    assert_equal 'closed', Scinote::ElnUi::ProjectProfile.find_by(project_id: scene[:project].id).status
  end

  def test_change_status_refuses_unsupported_states
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    status, body = post_status(scene[:creator], scene[:project], status: 'annual_review')

    assert_equal 422, status, '本轮无承载语义的状态不许静默存下'
    assert_includes body['error'].to_s, '已结题'
    refute scene[:project].reload.archived?, '失败的写入不能留下副作用'
  end

  def test_member_cannot_change_status
    scene = build_scene!
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :normal, name: 'pdmember2')

    status, = post_status(member, scene[:project], status: 'closed')

    assert_equal 403, status, '归档只归项目负责人（SCN-PM-ARCH-1）'
    refute scene[:project].reload.archived?
  end

  private

  def payload(scene)
    Scinote::ElnUi::ProjectDetailPayload.call(scene[:project])
  end

  def payload_permissions(project, user)
    Scinote::ElnUi::ProjectDetailPayload.permissions_for(project, user)
  end

  def patch_project(user, project, params)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.patch "/projects/#{project.id}/eln_project_detail",
                  params: params.to_json,
                  headers: { 'CONTENT_TYPE' => 'application/json' }
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end

  def post_status(user, project, params)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.post "/projects/#{project.id}/eln_project_detail/status",
                 params: params.to_json,
                 headers: { 'CONTENT_TYPE' => 'application/json' }
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end
end
