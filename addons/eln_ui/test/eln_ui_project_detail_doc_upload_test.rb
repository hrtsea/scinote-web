# frozen_string_literal: true

# ELN UI —— 必传文档行内上传 + show 懒补种 + task_book 退役壳（ADR-0049）
#
# 对拍铁律（变异测试逐条验过）：
#   1. upload_document 的 `return render_403 unless current_permissions[:canUploadDocs]`
#      摘掉 → restricted 成员 403 用例精确变红；
#   2. find_by! 的 `project_id: @project.id` 摘掉 → 跨项目 404 用例变红；
#   3. show 里的 `RequiredDocSeeder.seed!` 摘掉 → 懒补种用例变红。

require_relative 'test_helper'

begin
  require 'warden'
  require 'warden/test/helpers'
rescue LoadError
  nil
end

class ElnUiProjectDetailDocUploadTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  # ------------------------------------------------------------
  # 权限闸门：受限成员（看得见项目、不可传文档）403
  # ------------------------------------------------------------

  def test_restricted_member_cannot_upload_document
    scene = build_scene!
    doc = seed_required_doc(scene[:project], '项目任务书')
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :restricted, name: 'restricted1')

    status, = upload_document(member, scene[:project], doc.id)

    assert_equal 403, status
    refute doc.reload.uploaded, '被拒的写入不留副作用'
  end

  # ------------------------------------------------------------
  # owner 上传：200 + 返回全量 payload + 附件落盘 + uploaded_on=当天
  # ------------------------------------------------------------

  def test_owner_upload_returns_full_payload_and_attaches_file
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    Scinote::ElnUi::ProjectProfile.create!(project: scene[:project], status: 'running', business_code: 'UP-1')
    doc = seed_required_doc(scene[:project], '项目任务书')
    # 真实流里用户先打开页面（show 懒补种已补 5 类）才点上传；这里显式补一次，
    # 不把「上传端点兼任补种」这种规格外行为测进去。
    Scinote::ElnUi::RequiredDocSeeder.seed!(scene[:project])

    status, body = upload_document(scene[:creator], scene[:project], doc.id)

    assert_equal 200, status
    req = body['requiredDocs']
    assert_equal 5, req.size, '返回全量 payload（与指标 CRUD 同款，Q12=A）'
    row = req.find { |r| r['id'] == doc.id }
    assert row['uploaded'], '该行 uploaded=true'
    assert_equal Time.zone.today.to_s, row['date'], 'uploaded_on=当天（ELN 日期字符串铁律）'
    assert doc.reload.file.attached?, '文件本体落宿主 ActiveStorage'
    assert_equal scene[:creator].id, doc.uploader_id, '登记人=当前用户'
  end

  # ------------------------------------------------------------
  # 行 id 必须落在本项目的 required 行上：跨项目 404（不泄漏存在性）
  # ------------------------------------------------------------

  def test_upload_with_other_project_row_id_returns_404
    scene = build_scene!
    other_scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    foreign = seed_required_doc(other_scene[:project], '项目任务书')

    status, = upload_document(scene[:creator], scene[:project], foreign.id)

    assert_equal 404, status
    refute foreign.reload.uploaded, '越权写入零副作用'
  end

  # 不是 required 类的行（other）也不许走这个端点上传。
  def test_upload_with_other_category_row_id_returns_404
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    other = Scinote::ElnUi::ProjectDocument.create!(project_id: scene[:project].id,
                                                    category: 'other', name: '过程记录', position: 1)

    status, = upload_document(scene[:creator], scene[:project], other.id)

    assert_equal 404, status
  end

  # ------------------------------------------------------------
  # 缺 file：422（与指标 blank_name 同款显式拒绝，不静默成功）
  # ------------------------------------------------------------

  def test_upload_without_file_returns_422
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    doc = seed_required_doc(scene[:project], '项目任务书')

    status, = upload_document(scene[:creator], scene[:project], doc.id, file: nil)

    assert_equal 422, status
    refute doc.reload.uploaded
  end

  # ------------------------------------------------------------
  # task_book 退役壳：410 + 指路（旧 bundle 缓存 fail-fast，不 500 不静默 404）
  # ------------------------------------------------------------

  def test_legacy_task_book_route_returns_gone
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(scene[:creator], scope: :user) }
    session.post "/projects/#{scene[:project].id}/eln_project_detail/task_book",
                 params: { file: uploaded_fixture }

    assert_equal 410, session.response.status
    assert_includes session.response.body, 'document', '410 体要指路新端点'
  end

  # ------------------------------------------------------------
  # show 懒补种（D9）：已纳管项目打开页面即补齐 5 类；未纳管不补
  # ------------------------------------------------------------

  def test_show_lazily_seeds_required_docs_for_managed_project
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    Scinote::ElnUi::ProjectProfile.create!(project: scene[:project], status: 'running', business_code: 'LZ-1')

    payload = extract_payload(detail_page(scene[:creator], scene[:project]))

    assert_equal 5, payload['requiredDocs'].size, 'show 打开即补种 5 类（懒补种 D9）'
    assert_equal 5, Scinote::ElnUi::ProjectDocument.where(project_id: scene[:project].id,
                                                          category: 'required').count,
                 '补种落在真库，不是响应体里临时凑的'
  end

  def test_show_does_not_seed_for_unmanaged_project
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    payload = extract_payload(detail_page(scene[:creator], scene[:project]))

    assert_equal [], payload['requiredDocs'], '无 profile 的项目维持空态，不拿固定清单顶（D6）'
  end

  private

  # GET 详情页（integration session，与 ElnUiProjectDetailTest#open_detail 同款），
  # 返回渲染出的 HTML —— payload 注入块就在里面。
  def detail_page(user, project)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.get("/projects/#{project.id}/eln_project_detail")
    assert_equal 200, session.response.status, '负责人应能打开项目详情页'
    session.response.body
  end

  def seed_required_doc(project, name)
    Scinote::ElnUi::ProjectDocument.create!(project_id: project.id, category: 'required',
                                            name: name, position: 1)
  end

  def upload_document(user, project, id, file: uploaded_fixture)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    params = { id: id }
    params[:file] = file if file
    session.post "/projects/#{project.id}/eln_project_detail/document", params: params
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end

  def uploaded_fixture
    path = Rails.root.join('tmp', 'doc_upload_test.pdf')
    File.binwrite(path, '%PDF-1.4 doc upload test fixture')
    Rack::Test::UploadedFile.new(path.to_s, 'application/pdf')
  end

  # show 的 payload 注入块（show.html.erb:17-19）—— 与 entry 读的是同一个 JSON 源。
  def extract_payload(html)
    matched = html.match(/id="eln-project-detail-data"[^>]*>\s*(.*?)\s*<\/script>/m)
    refute_nil matched, '详情页必须注入 #eln-project-detail-data JSON 块'
    JSON.parse(matched[1])
  end
end
