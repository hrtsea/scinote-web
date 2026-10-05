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
      qty: '8', unit: 'kg', unit_price: '320', purpose: '测试用' }.merge(overrides)
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
end
