# frozen_string_literal: true
#
# D10 —— 矩阵页前端资产（只在真实浏览器里炸的那类问题）
#
# 背景（实测踩坑）：
# 生产容器 `scinote_web_production` 里 `config/initializers/content_security_policy.rb`
# 把 script-src 设成 `self + nonce`，且 `content_security_policy_nonce_directives =
# %w(script-src)`。矩阵页原来用**行内 <script>** 绑开关点击，在真实 Chromium 里被 CSP
# 拦掉 —— 点击开关**毫无反应**（单元测试全绿、jsdom 也测不出来，只有真浏览器抓得到）。
# 修法：行内 script 带上 `nonce="<%= content_security_policy_nonce %>"`。
#
# 这条测试给该回归上保险：渲染矩阵页，断言行内脚本是「带 nonce 的合法脚本」，
# 且里面确实有开关用的 fetch 逻辑；顺带守住「越权直开矩阵 URL 返回 403」。

require_relative 'test_helper'

class D10ViewAssetTest < AcTest::Base
  def test_matrix_page_renders
    scene = build_scene!
    make_experiment!(project: scene[:project], creator: scene[:creator])

    res = open_matrix(scene[:creator], scene[:project])

    assert_equal 200, res[:status], '负责人应能打开矩阵页'
    assert_includes res[:html], 'id="acMatrixTable"', '矩阵表格应渲染出来'
  end

  def test_inline_toggle_script_carries_csp_nonce
    scene = build_scene!
    make_experiment!(project: scene[:project], creator: scene[:creator])

    res = open_matrix(scene[:creator], scene[:project])

    # 行内脚本必须带 nonce，否则生产 CSP 直接拦掉、开关点了没反应
    assert_match(/<script[^>]*\bnonce="[^"]+"[^>]*>/, res[:html],
                 '矩阵页行内 <script> 必须带 CSP nonce（script-src 只有 self+nonce）')
  end

  def test_inline_script_actually_contains_the_toggle_fetch
    scene = build_scene!
    make_experiment!(project: scene[:project], creator: scene[:creator])

    res = open_matrix(scene[:creator], scene[:project])

    scripts = res[:html].scan(/<script\b[^>]*>(.*?)<\/script>/m).flatten
    toggle  = scripts.find { |s| s.include?('visibility_matrix/') && s.include?('fetch') }
    refute_nil toggle, '应存在含 fetch(toggle-路径) 的开关逻辑'
  end

  def test_member_is_denied_the_matrix_page
    scene = build_scene!
    make_experiment!(project: scene[:project], creator: scene[:creator])
    member = add_restricted_member!(scene[:project], scene[:team], assigner: scene[:creator])

    res = open_matrix(member, scene[:project])

    assert_equal 403, res[:status], '受限成员直接打矩阵 URL 应被控制器挡下（不是前端藏按钮）'
    refute_includes res[:html], 'id="acMatrixTable"'
  end

  # D10.1 —— 图标类名必须是**真实存在**的（生产实拍：epp 导电项目矩阵页糊成一片字符，
  # 现场查下来是 `sn-icon-check-circle` / `sn-icon-close-circle` 在 SciNote 图标字体里
  # 根本不存在（sn-icon-font.css 只有 232 个类）→ ::before 没有 content → <i> 尺寸为 0，
  # 开关长期没有任何状态标识）。
  def test_switch_icons_are_real_sn_icon_classes
    scene = build_scene!
    make_experiment!(project: scene[:project], creator: scene[:creator])

    res = open_matrix(scene[:creator], scene[:project])

    html = res[:html]
    assert_match(/sn-icon-check/, html, '放行态开关应使用图标字体里存在的 sn-icon-check')
    assert_match(/sn-icon-close/, html, '未放行态开关应使用图标字体里存在的 sn-icon-close')
    refute_match(/sn-icon-(check|close)-circle/, html,
                 '历史错误类名 sn-icon-*-circle 在图标字体里不存在，会渲染成 0 尺寸的空 <i>')

    css = sn_icon_font_css
    %w[sn-icon-check sn-icon-close].each do |klass|
      assert_match(/\.#{Regexp.escape(klass)}:before/, css, "#{klass} 必须在 sn-icon-font.css 里有 :before 规则")
    end
  end

  # D10.2 —— 列宽下限 + 标签不许换行（生产实拍第 2 个来源）：
  # epp 导电项目 57 个实验，实验列没有 min-width，表格被压到每列 24px，
  # 表头实验名与「任务」标签竖排溢出，整页糊成字符流。修法：th 固定 156px（页面规格 §4.1 V1.1，
  # 原型实测末列开关需 ≥152px）+ 表格 max-content 下限交给横向滚动 + 标签 nowrap。
  def test_matrix_layout_keeps_columns_readable
    scene = build_scene!
    make_experiment!(project: scene[:project], creator: scene[:creator])

    res = open_matrix(scene[:creator], scene[:project])

    assert_match(/min-width:\s*156px/, res[:html], '实验列必须有 156px 下限（页面规格 §4.1 V1.1）')
    assert_match(/#acMatrixTable\s*\{[^}]*min-width:\s*max-content/, res[:html],
                 '表格要有 max-content 下限，否则会被压窄列')
    assert_match(/\.ac-cell-task\s*\{[^}]*white-space:\s*nowrap/, res[:html],
                 '「任务」标签必须 nowrap，否则窄列里竖排成 t/a/s/k/s')
  end

  private

  # Warden::Test::Helpers 才提供 Warden.on_next_request（warden/test/helpers）
  include Warden::Test::Helpers

  def sn_icon_font_css
    path = Rails.root.join('vendor/assets/stylesheets/sn-icon-font.css')
    File.read(path)
  end

  def open_matrix(user, project)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
    session.get("/access_permissions/projects/#{project.id}/visibility_matrix")
    { status: session.response.status, html: session.response.body }
  end
end
