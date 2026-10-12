# frozen_string_literal: true

# ELN UI —— 其他文档上传 + 附件预览/下载端点（ADR-0050）
#
# 对拍铁律（变异测试逐条验过）：
#   1. create_document 的 canUploadDocs 守门摘掉 → restricted 403 用例精确变红；
#   2. send_document_file 的 `project_id: @project.id` 摘掉 → 跨项目 404 用例变红；
#   3. send_document_file 的 `file.attached?` 守门摘掉 → 无附件 404 用例变红。
#
# 权限档位（Q3=B）：预览/下载只守**读权限**（before_action 已守）——
#   受限成员（看得见项目、不可传）也能预览/下载，case 7 是这条的兑现验证。

require_relative 'test_helper'

begin
  require 'warden'
  require 'warden/test/helpers'
rescue LoadError
  nil
end

class ElnUiProjectDetailDocActionsTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  # ------------------------------------------------------------
  # create_document：owner 建 other 新行，元数据全自动（Q7=A）
  # ------------------------------------------------------------

  def test_owner_create_other_doc_row_with_auto_metadata
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    status, body = create_document(scene[:creator], scene[:project], '测试文档.PDF')

    assert_equal 200, status
    others = body['otherDocs']
    assert_equal 1, others.size, '新行出现在 otherDocs（全量 payload，Q12 同款）'
    row = others.first
    assert_equal '测试文档.PDF', row['name'], 'name=文件名原样（含扩展名，同项目 36 历史数据形态）'
    assert_equal 'pdf', row['type'], 'doc_type=扩展名 downcase（.PDF → pdf）'
    assert_equal scene[:creator].full_name, row['by'], '上传人=当前用户'
    assert_equal Time.zone.today.to_s, row['date'], '上传时间=当天（ELN 日期字符串铁律）'

    doc = Scinote::ElnUi::ProjectDocument.find_by(project_id: scene[:project].id, name: '测试文档.PDF')
    assert doc, '落真库，不是响应体里凑的'
    assert_equal 'other', doc.category
    assert doc.uploaded, '建行即 uploaded=true（附件已随行落盘）'
    assert doc.file.attached?, '文件本体走宿主 ActiveStorage'
  end

  def test_create_document_appends_position
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    Scinote::ElnUi::ProjectDocument.create!(project_id: scene[:project].id, category: 'other',
                                            name: '旧记录.xlsx', position: 7, uploaded: true)

    create_document(scene[:creator], scene[:project], '新记录.csv')

    new_row = Scinote::ElnUi::ProjectDocument.find_by(project_id: scene[:project].id, name: '新记录.csv')
    assert_equal 8, new_row.position, 'append：最大+1，不做重排（与指标同口径）'
  end

  # ------------------------------------------------------------
  # create_document：权限与缺文件显式拒绝
  # ------------------------------------------------------------

  def test_restricted_member_cannot_create_document
    scene = build_scene!
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :restricted, name: 'restricted1')

    status, = create_document(member, scene[:project], '越权.pdf')

    assert_equal 403, status
    assert_equal 0, Scinote::ElnUi::ProjectDocument.where(project_id: scene[:project].id,
                                                          category: 'other').count,
                 '被拒的创建不留副作用'
  end

  def test_create_document_without_file_returns_422
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])

    status, = create_document(scene[:creator], scene[:project], nil_file: true)

    assert_equal 422, status
    assert_equal 0, Scinote::ElnUi::ProjectDocument.where(project_id: scene[:project].id,
                                                          category: 'other').count,
                 '无文件不建空行'
  end

  # ------------------------------------------------------------
  # 预览/下载：attached 行 302 到 blob URL，disposition 分流
  # ------------------------------------------------------------

  def test_preview_redirects_to_blob_with_inline_disposition
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    doc = attached_other_doc(scene[:project], '任务书.pdf')

    status, location = fetch_document(scene[:creator], scene[:project], doc.id, mode: 'preview')

    assert_equal 302, status
    assert_includes location, '/rails/active_storage/blobs/redirect/', 'redirect 到宿主 ActiveStorage'
    # Rails 7.2：disposition 是 query 参数（不是路径段 (.:disposition)）
    assert_includes location, 'disposition=inline', 'inline disposition'
  end

  def test_download_redirects_to_blob_with_attachment_disposition
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    doc = attached_other_doc(scene[:project], '任务书.pdf')

    status, location = fetch_document(scene[:creator], scene[:project], doc.id, mode: 'download')

    assert_equal 302, status
    assert_includes location, 'disposition=attachment', 'attachment disposition（Rails 7.2 query 参数形态）'
  end

  # ------------------------------------------------------------
  # 预览/下载：404 两种 —— 无附件行 / 跨项目行（不泄漏存在性）
  # ------------------------------------------------------------

  def test_fetch_document_without_attachment_returns_404
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    doc = Scinote::ElnUi::ProjectDocument.create!(project_id: scene[:project].id, category: 'other',
                                                  name: '占位无附件', position: 1)

    %w[preview download].each do |mode|
      status, = fetch_document(scene[:creator], scene[:project], doc.id, mode: mode)
      assert_equal 404, status, "#{mode}: 无附件行没有文件可读"
    end
  end

  def test_fetch_document_with_other_project_row_id_returns_404
    scene = build_scene!
    other_scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    foreign = attached_other_doc(other_scene[:project], '别人的.pdf')

    %w[preview download].each do |mode|
      status, = fetch_document(scene[:creator], scene[:project], foreign.id, mode: mode)
      assert_equal 404, status, "#{mode}: 行不在本项目一律 404（不泄漏存在性）"
    end
  end

  # ------------------------------------------------------------
  # Q3=B：受限成员（可读、不可传）也能预览/下载
  #   读权限与整页同源（before_action 已守），附件不额外设限。
  # ------------------------------------------------------------

  def test_restricted_member_can_preview_and_download
    scene = build_scene!
    make_project_owner!(scene[:project], user: scene[:creator])
    doc = attached_other_doc(scene[:project], '过程记录.pdf')
    member = add_member!(scene[:project], scene[:team], assigner: scene[:creator], role: :restricted, name: 'restricted1')

    %w[preview download].each do |mode|
      status, location = fetch_document(member, scene[:project], doc.id, mode: mode)
      assert_equal 302, status, "#{mode}: 可读者即可下载（Q3=B）"
      assert_includes location, 'active_storage'
    end
  end

  private

  def create_document(user, project, filename = nil, nil_file: false)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    params = {}
    params[:file] = uploaded_fixture(filename) unless nil_file
    session.post "/projects/#{project.id}/eln_project_detail/documents", params: params
    [session.response.status, (JSON.parse(session.response.body) rescue {})]
  end

  def fetch_document(user, project, id, mode:)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.get "/projects/#{project.id}/eln_project_detail/documents/#{id}/#{mode}"
    [session.response.status, session.response.location.to_s]
  end

  def attached_other_doc(project, filename)
    doc = Scinote::ElnUi::ProjectDocument.create!(project_id: project.id, category: 'other',
                                                  name: filename, position: 1, uploaded: true)
    doc.file.attach(uploaded_fixture(filename))
    doc
  end

  def uploaded_fixture(filename = 'fixture.pdf')
    path = Rails.root.join('tmp', filename)
    File.binwrite(path, '%PDF-1.4 doc actions test fixture')
    Rack::Test::UploadedFile.new(path.to_s, 'application/pdf')
  end
end
