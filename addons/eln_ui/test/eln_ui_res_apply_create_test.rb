# frozen_string_literal: true

# ELN UI —— 新建资源申请端点 POST /eln_res_applications（SCN-RES-APPLY-1）
#
# 🔴 为什么必须是**集成测试**（而不是像其它用例那样只测 payload 装配）：
#   这条链路是 addon 里唯一一个「请求进 → 落 addon 自有表」的写入口，
#   2026-10-05 真机才暴露它一存在就是 500（ActionController::Parameters 上根本没有
#   expect 方法，rescue 里写的 ParameterTypeError 常量也不存在 → 双重崩），
#   而当时 92 条用例全绿 —— 因为没有任何用例真正打过这个 POST。
#   所以这里走真路由（Integration::Session）打进去，钉死：
#     ① 正常申请 → 200 + 合法编号 + 库里真有一行
#     ② 字段缺失/非法 → 422 + 中文业务提示（绝不能漏成 500）
#
# ⚠ 为什么继承 AcTest::Base 而不是 ActionDispatch::IntegrationTest：
#   造数 helper（build_scene! / make_user! …）是 AcTest::Base 的私有实例方法，
#   而 include AcTest::Base 会报「wrong argument type Class (expected Module)」
#   （Class 不能 include）；改用 Integration::Session 手动发请求，
#   既拿到 Base 的事务包裹（跑完 Rollback，不污染 test 库），又能打真路由。
require_relative 'test_helper'

class ElnUiResApplyCreateTest < AcTest::Base
  include Warden::Test::Helpers
  include ElnUiFactories

  def setup
    @scene   = build_scene!
    @user    = @scene[:creator]
    @team    = @scene[:team]
    @project = @scene[:project]
    # check_team_membership 走 ApplicationController#current_team
    # （current_user.current_team_id → teams.find_by）—— 集成路径必须自己指过去，否则 403。
    @user.update!(current_team_id: @team.id)
    # 材料类申请的目标库（ADR-0030 D7 起必填：申请时就要选定料进哪个库）
    @repository = target_repository(team: @team, creator: @user)
    @session = ActionDispatch::Integration::Session.new(Rails.application)
  end

  def post_apply(attrs)
    Warden.on_next_request { |proxy| proxy.set_user(@user, scope: :user) }
    @session.post '/eln_res_applications',
                  params: attrs.to_json,
                  headers: { 'CONTENT_TYPE' => 'application/json' }
    [(@session.response.status rescue 500), (JSON.parse(@session.response.body) rescue {})]
  end

  def valid_attrs(overrides = {})
    { project_id: @project.id, kind: 'material', name: '_test_ 基料',
      qty: '8', unit: 'kg', unit_price: '320', purpose: '测试用',
      # 材料类必填（ADR-0030 D7）。**必须走白名单传参** —— 漏进 permit 名单就是
      # 「字段静默丢失」，而这类丢失在单测里最难发现（请求 200、单据却在没有目标库的状态）。
      repository_id: @repository.id }.merge(overrides)
  end

  # ① 正常：建草稿 → 200 + 编号合法 + 库里真有一行
  def test_create_draft_returns_ok_and_generated_no
    status, body = post_apply(valid_attrs)

    assert_equal 200, status, "body=#{body}"
    assert_equal true, body['ok']
    assert_match(/\ASQ-\d{4}-\d{4}\z/, body['no'].to_s)
    assert_equal 'draft', body['status']

    app = Scinote::ElnUi::ResourceApplication.find_by(no: body['no'])
    refute_nil app, '编号必须真落库（不只是回包）'
    assert_equal @project.id, app.project_id
    # item_list 读侧是 with_indifferent_access：'qty' / :qty 都能取（写侧存的是字符串键）
    assert_equal 8.to_d, app.item_list.first['qty'].to_d
    assert_equal 'kg', app.item_list.first['unit']
    assert_equal '_test_ 基料', app.item_list.first['name']
    assert_equal 320.to_d, app.item_list.first['unit_price'].to_d
  end

  # ② 缺项目 → 422 业务提示，**不能是 500**
  def test_missing_project_returns_422_not_500
    status, body = post_apply(valid_attrs(project_id: nil))

    assert_equal 422, status, "body=#{body}"
    assert_equal false, body['ok']
    assert_includes body['error'].to_s, '请选择申请项目'
  end

  # ⑤ 归档项目 → 422（fail-closed：下拉已排除归档，后端再次兜底；SCN-RES-APPLY-5）
  def test_archived_project_rejected
    @project.update!(archived: true)
    status, body = post_apply(valid_attrs(project_id: @project.id))

    assert_equal 422, status, "body=#{body}"
    assert_equal false, body['ok']
    assert_includes body['error'].to_s, '项目已归档'
  end

  # ③ 数量填了非法值 → 仍是 422（类型不硬转，交给 service 判），不是 500
  def test_invalid_qty_returns_422_not_500
    status, body = post_apply(valid_attrs(qty: 'abc'))

    assert_equal 422, status, "body=#{body}"
    assert_includes body['error'].to_s, '数量必须大于 0'
  end

  # ④ 非法资源类型 → 422
  def test_bad_kind_returns_422
    status, body = post_apply(valid_attrs(kind: 'nonsense'))

    assert_equal 422, status, "body=#{body}"
    assert_includes body['error'].to_s, '资源类型'
  end

  # ⑤ 完全空 body → 422（缺键补 nil 的兜底路径，正是当年 500 的另一半）
  def test_empty_body_returns_422
    status, body = post_apply({})

    assert_equal 422, status, "body=#{body}"
    assert_equal false, body['ok']
  end

  # ⑥ 🔴 绑定参数必须能穿过 controller 的 permit 名单落到库里（SCN-RES-APPROVE-3 / SQ-2026-7783）
  #   本文件开头那条教训的翻版：**permit 名单里少写一个键，整个绑定就静默丢失**，
  #   而 service 层单测（直接传 kwarg）永远发现不了 —— 因为它在 controller 之后。
  #   这条用例是唯一能钉死「HTTP 参数名 ↔ permit 白名单 ↔ service 形参」三者对齐的用例。
  #   ⚠ 请购语义（ADR-0030）：材料类绑的是「目标库」(repository_id)，不是已存在的条目。
  def test_create_draft_persists_repository_and_module_binding
    repo = make_active_repository!(team: @team, creator: @user)
    task = build_task_for(@scene)

    status, body = post_apply(valid_attrs(repository_id: repo.id, my_module_id: task.id))
    assert_equal 200, status, "body=#{body}"

    app = Scinote::ElnUi::ResourceApplication.find_by(no: body['no'])
    refute_nil app
    assert_equal repo.id, app.repository_id, 'permit 名单漏了 repository_id → 目标库静默丢失'
    assert_equal task.id, app.my_module_id, 'permit 名单漏了 my_module_id → 关联任务静默丢失'
  end

  # ⑦ 绑到别团队的库 → 422 业务提示（不是 500，也不是静默接受）
  def test_binding_repository_from_other_team_returns_422
    other_team = ::Team.create!(name: "other-#{SecureRandom.hex(3)}", created_by: @user)
    other_repo = make_active_repository!(team: other_team, creator: @user)

    status, body = post_apply(valid_attrs(repository_id: other_repo.id))
    assert_equal 422, status, "body=#{body}"
    assert_includes body['error'].to_s, '不属于当前团队'
  end

  # ⑧ 关联任务不在所选项目下 → 422（前端已按项目过滤，但接口不能只靠前端把关）
  def test_binding_task_outside_project_returns_422
    other_project = ::Project.create!(
      team: @team, name: "other-proj-#{SecureRandom.hex(3)}", created_by: @user,
      last_modified_by: @user, visibility: :hidden, template: false
    )
    other_exp = make_experiment!(project: other_project, creator: @user)
    other_task = make_task!(experiment: other_exp, creator: @user)

    status, body = post_apply(valid_attrs(my_module_id: other_task.id))
    assert_equal 422, status, "body=#{body}"
    assert_includes body['error'].to_s, '任务不属于该项目'
  end
end
