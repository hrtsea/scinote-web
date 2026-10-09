# frozen_string_literal: true

# AI 协议解析 addon —— 「入口归属」护栏
#
# ## 背景（2026-10-09 真机取证，见 .workbuddy/memory/2026-10-09.md §14:00）
#   /protocols 列表页上一度同时有**两颗** "Create with AI"，归属完全不同：
#     · 工具栏那颗（渐变描边 + sn-icon-ai，`[data-e2e="e2e-BT-topToolbar-import_ai"]`）
#       → **宿主原生**：app/javascript/vue/protocols/table.vue（上游提交 SCI-12877）；
#     · 标题行右上角那颗蓝色 `btn btn-primary pull-right`（id="createProtocolWithAi"）
#       → **addon 自己 deface 插的**，指向 legacy 无 JS 页 /ai_protocols/new。
#   官方（my.scinote.net）只有原生两处入口：列表页工具栏 + 详情页 Options 下拉。
#   故 addon 自建那颗已删除（app/overrides/ai_protocol_create_button.rb 不再存在）。
#
# ## 本用例锁的四条不变量
#   ① 挂载点必须在：原生按钮点击时走 `document.querySelector('#importWithAI').click()`，
#      而该触发器由 addon 的 AiParserContainer 渲染 ⇒ 没有容器，原生入口点了没反应
#      （这正是详情页曾出现的 `containers:0` 病根，protocols 页走 layouts/fluid）。
#   ② 注册表里**不得**存在面向 protocols/index 的 override —— 这是本次「摘掉自建按钮」
#      的根护栏。⚠ 它必须是**运行时注册表**检查而不是「页面 HTML 里没有按钮」那种断言：
#      入口按钮的渲染还压着两道业务门（Protocol.ai_parser_enabled? 与
#      can_generate_protocol_with_ai?），门没开时按钮本来就渲染不出来 —— 只断言
#      「页面没有按钮」会**空洞通过**，护栏等于不存在。注册表检查与门控无关，非空洞。
#   ③ 反向依赖：入口既然只剩宿主原生那两处，那两处 + 隐藏触发器就是**唯一入口链**，
#      上游升级误删/改名时必须红 —— 否则 AI 会静默退化成「没有入口」。
#   ④ 两个 layout 都要挂（application + fluid），少一个就是详情页点不动。
require_relative 'test_helper'
require 'warden'
require 'warden/test/helpers'

class AiProtocolsLibraryEntryTest < AcTest::Base
  include Warden::Test::Helpers

  def setup
    @scene = build_scene!
    @user  = @scene[:creator]
  end

  def protocols_page
    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(@user, scope: :user) }
    session.get '/protocols'
    session
  end

  # ---------- ① 挂载点必须在，且在 .sci--layout-content 之内 ----------
  def test_parser_container_is_injected_inside_layout_content
    res = protocols_page
    assert_equal 200, res.response.status
    body = res.response.body

    assert_includes body, 'id="aiParserContainer"',
                    'addon 必须注入弹窗挂载点（原生入口靠它开弹窗）'

    anchor = body.index('sci--layout-content')
    mount  = body.index('aiParserContainer')
    refute_nil anchor, '列表页应渲染宿主 .sci--layout-content（Deface 的挂载锚点）'
    assert_operator anchor, :<, mount,
                    '挂载点必须落在 .sci--layout-content 之内'
  end

  # Deface::Override.all 的形状（实测）：`{ virtual_path(Symbol) => { name(String) => Override } }`
  def registered_virtual_paths
    Deface::Override.all.keys.map(&:to_s)
  end

  # ---------- ② 注册表：不得存在面向 protocols/index 的 override（根护栏） ----------
  def test_no_registered_override_targets_protocols_index
    paths = registered_virtual_paths
    refute_empty paths, 'Deface 注册表为空 ⇒ 本用例失去意义（override 根本没被加载）'

    refute_includes paths, 'protocols/index',
                    'addon 不得再向 protocols/index 注入任何东西（自建入口按钮的来源）；' \
                    "当前注册的 override：#{Deface::Override.all[:"protocols/index"]&.keys.inspect}"
  end

  # ---------- ③ 两个 layout 都得挂容器（少了 fluid ⇒ 详情页点不动） ----------
  def test_parser_container_registered_for_both_layouts
    paths = registered_virtual_paths
    assert_includes paths, 'layouts/application', 'application layout 缺少挂载点'
    assert_includes paths, 'layouts/fluid',
                    'fluid layout 缺少挂载点 —— protocols 列表/详情页走的就是 fluid'
  end

  # ---------- ④ 行为面兜底：页面里不应出现 legacy 自建入口的痕迹 ----------
  def test_legacy_entry_traces_are_absent_from_the_page
    body = protocols_page.response.body

    refute_includes body, 'createProtocolWithAi',
                    'addon 不得再注入自建入口按钮（官方入口只在宿主原生按钮上）'
    refute_includes body, '/ai_protocols/new',
                    '列表页不应再出现 legacy 入口链接（该页只作无 JS 降级，不设入口）'
  end

  # ---------- ⑤ 反向依赖：原生入口链必须仍在 ----------
  def test_native_entry_chain_still_exists_in_source
    table = Rails.root.join('app/javascript/vue/protocols/table.vue').read
    assert_includes table, "name: 'import_ai'",
                    '列表页工具栏原生入口（protocols/table.vue 的 import_ai）缺失'
    assert_includes table, 'sn-icon-ai', '列表页原生入口的 AI 图标缺失'

    opts = Rails.root.join('app/javascript/vue/protocol/protocolOptions.vue').read
    assert_includes opts, 'importWithAI',
                    '详情页 Options 下拉的原生入口（protocolOptions.vue）缺失'

    container = Rails.root.join('addons/ai_protocols/app/javascript/vue/AiParserContainer.vue').read
    assert_includes container, 'id="importWithAI"',
                    '隐藏触发器 #importWithAI 缺失 ⇒ 宿主原生入口点了无反应'
  end
end
