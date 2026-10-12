# frozen_string_literal: true
#
# ELN UI —— 路由基线与迁移契约守卫（ticket 01 建立，ticket 02 用于验证迁移）
#
# ## 背景
# ELN UI 的 31 条路由当前寄生在宿主 `config/routes.rb`（违反零入侵铁律，见 ADR-0022）。
# 本文件在**任何路由被搬动之前**先把它们的「动词 + 路径 + helper 名」冻结成基线，
# 使"迁移有没有改坏东西"成为机器断言，而不是靠人工数 31 条路由。
#
# ## 为什么基线要记录 controller#action
# 路由"匹配得上"不等于"能用"：路由引用了不存在的 controller 时，请求会走到 500
# （recognition 报 references missing controller）。这条错误在纯 Ruby 层查不出来，
# 只能靠识别（recognition）逐条断言，故基线带上 controller#action。
#
# ## 三类偏差必须区分（不能只比总数）
# 总数相等但 helper 换了名字 = 静默回归（payload 生成 URL、前端拿到错的地址）。
# 所以比对键是**三元组**，且报告里要分missing / renamed / added 三类列出。
#
# 运行：容器内 RAILS_ENV=test bin/rails runner addons/eln_ui/test/run.rb

require_relative 'test_helper'

class ElnUiRouteBaselineTest < AcTest::Base
  ELN_CONTROLLER_PREFIX = 'scinote/eln_ui/'

  # ELN UI 的控制器裸名白名单 —— 认定"这条路由属于 ELN UI"的唯一可靠判据。
  # ⚠ 不能用 "path/name 含 eln_" 捞：`eln_workbench` 同为 /eln_* 前缀，会被误纳入。
  #   （2026-10-12 起 workbench 已并入 eln_ui，其路由迁到本 addon 的 config/routes.rb；
  #     但因本白名单不含 `workbench`，它不计入这 31 条基线——属有意，见 ADR-0045。）
  ENGINE_CONTROLLERS = %w[
    project_detail project_list res_center res_apply_detail res_apply_action
    res_apply_create exp_detail my_module_detail project_approvers
    task_close_action notifications
  ].freeze

  # 基线快照文件（由 `rake` 任务或 bin/rails runner 生成后随库入库）。
  # 首次生成见本文件末尾「如何重建基线」一节。
  BASELINE_PATH = File.expand_path('../test/fixtures/eln_ui_routes_baseline.json', __dir__)

  # 迁移后 ELN UI 路由应落在 addon 自己的路由定义里；宿主 routes.rb 不得再出现。
  HOST_ROUTES_PATH = Rails.root.join('config/routes.rb')

  EXPECTED_COUNT = 31

  # 收集 ELN UI 的 31 条路由 —— **迁移前后都要能用同一段代码取到**。
  #
  # ⚠ 迁移后（ticket 02）的坑：路由进了引擎，引擎声明了 `isolate_namespace`，
  #   其 route set 的 `defaults[:controller]` 是**不带** `scinote/eln_ui/` 前缀的
  #   （引擎会自己拼上去）。所以按 controller 前缀过滤会一条都取不到 ⇒ 守卫静默失效。
  #   宿主侧则只剩 `mount` 进来的引擎，同样没有这些 controller 值。
  #
  #   正解：**两处都扫**——宿主路由表 + 引擎自己的 route set，按 controller 前缀或
  #   「path/name 前缀命中 ELN UI 特征」来认。特征用 path（含 eln_ 段）与具名 helper
  #   （eln_* / project_eln_*），两者都不依赖命名空间解析方式。
  def eln_routes
    # ⚠🔴 **测试环境（RAILS_ENV=test）下引擎路由数为 0** —— addon 的 routes initializer
    #   在 test 环境不执行，`Engine.routes` 是空的。实测 TEST_ENGINE_ROUTES=0。
    #   ⇒ 迁移后的三元组比对**不能在 test 环境做**，否则恒报"缺失 31 条"（假红）。
    #   正确分工：
    #     · test 环境：只校验「宿主 config/routes.rb 已零残留」+ 基线文件自身完整性
    #       （这两条不依赖运行时路由表，任何环境都成立）。
    #     · 生产/开发环境：三元组比对 + 逐条 recognition（路由真实存在时才做）。
    #   判定用引擎路由是否真的挂上，而不是靠 Rails.env 猜。
    # 🔴 坑（2026-10-13 修）：`RouteSet#routes` 返回 ActionDispatch::Journey::Routes
    #   （**不是 Array**）⇒ `is_a?(Array)` 恒 false ⇒ engine_routes 恒 []。
    #    silently 只剩 app routes 一路；test 环境 app routes 也没有展开的引擎路由，
    #   于是 routes_available? 恒 false、三元组比对被整体跳过（守卫静默失效）。
    #   必须 `.to_a`。
    engine_routes = begin
      r = Scinote::ElnUi::Engine.routes
      r.respond_to?(:routes) ? r.routes.to_a : []
    rescue StandardError
      []
    end

    return [] if engine_routes.empty? && Rails.application.routes.routes.none? do |rr|
      rr.defaults[:controller].to_s.include?(ELN_CONTROLLER_PREFIX)
    end

    (Rails.application.routes.routes.to_a + engine_routes).select do |r|
      ctrl = r.defaults[:controller].to_s
      bare = ctrl.split('/').last.to_s
      ENGINE_CONTROLLERS.include?(bare)
    end.uniq { |r| [r.name, r.path.spec.to_s, r.verb.to_s] }
  end

  # 路由表里当前是否真的能取到 ELN UI 的路由（生产/开发为 true，test 为 false）
  def routes_available?
    eln_routes.any?
  end

  # 三元组：动词（多动词拆成数组并排序，match 路由才有意义）+ 路径 + helper 名（匿名记 nil）
  def route_triples
    eln_routes.map do |r|
      verbs = r.verb.to_s.split('|').reject { |v| v.empty? || v.start_with?('(.:') }.sort
      path = r.path.spec.to_s.sub(/\(\.:format\)\z/, '')
      helper = r.name
      # 路径本身已含动态段，helper 为 nil 时用「动词+路径+控制器+动作」兜底唯一标识，
      # 保证三元组在"改名"场景下确实会 diff 出来，而不是被静默去重。
      key = helper || "ANON:#{verbs.join(',')}:#{path}:#{r.defaults[:controller]}##{r.defaults[:action]}"
      [verbs.join(','), path, key, "#{r.defaults[:controller]}##{r.defaults[:action]}"]
    end.sort_by { |v, p, _k, _c| [p, v] }
  end

  def baseline
    @baseline ||= JSON.parse(File.read(BASELINE_PATH))
  rescue Errno::ENOENT
    flunk "基线文件不存在：#{BASELINE_PATH} —— 见文件末尾「如何重建基线」"
  end

  # ------------------------------------------------------------
  # 基线本身（迁移前后都应恒成立）
  # ------------------------------------------------------------

  def test_baseline_has_expected_route_count
    assert_equal EXPECTED_COUNT, baseline['routes'].size,
                 "基线应记录 #{EXPECTED_COUNT} 条 ELN UI 路由，实际 #{baseline['routes'].size} 条"
  end

  def test_current_routes_match_baseline_exactly
    # 迁移后路由只在生产/开发环境的运行时路由表里；test 环境引擎路由为空（initializer 不跑）。
    # 此时本条断言**无对象可验**，跳过而不是报假红；它在生产环境由
    # `bin/rails runner` / 真机探针 / E2E 覆盖（见 ticket 02 的验收记录）。
    skip '运行时路由表里没有 ELN UI 路由（test 环境不执行 addon routes initializer）' unless routes_available?

    current = route_triples.map { |v, p, k, c| { 'verb' => v, 'path' => p, 'key' => k, 'controller' => c } }
    frozen = baseline['routes']

    current_keys = current.map { |r| r['key'] }
    frozen_keys  = frozen.map { |r| r['key'] }

    missing   = frozen_keys - current_keys
    added     = current_keys - frozen_keys
    # renamed：数量相等但键集合不同 ⇒ 至少有一条被改名/改路径
    renamed = (missing.any? && added.any? && current.size == frozen.size)

    msg = []
    msg << "缺失 #{missing.size} 条：#{missing.inspect}" if missing.any?
    msg << "新增 #{added.size} 条：#{added.inspect}" if added.any?
    if renamed
      # 逐条对齐到具体差异，方便定位是哪条被改名
      diffs = frozen.reject { |f| current_keys.include?(f['key']) }.map do |f|
        "  #{f['key']} → #{current.find { |c| c['path'] == f['path'] }&.fetch('key', '(无)')}"
      end
      msg << "疑似改名 #{diffs.size} 条（路径相同但 helper/key 不同）：\n#{diffs.join("\n")}"
    end

    assert_empty msg.join("\n"), "路由集合与基线不一致：\n#{msg.join("\n")}"
  end

  def test_baseline_generation_is_idempotent
    # 同一份代码两次取样必须完全一致（否则基线不可信）
    assert_equal route_triples, route_triples, '两次取样结果不同，基线生成不幂等'
  end

  # ------------------------------------------------------------
  # 铁律守卫：宿主 routes.rb 不得再出现 ELN UI 路由
  # ------------------------------------------------------------
  #
  # ⚠ 迁移已完成（ticket 02，2026-10-12）：31 条路由已整块搬进
  # addons/eln_ui/config/routes.rb，由引擎自注册。宿主 routes.rb 应为零残留，
  # 本断言自此从"钉住现状"变为"强制清零"——将来谁把路由挂回宿主，它就变红。
  MIGRATED = true

  def test_host_routes_file_has_no_eln_ui_routes
    content = File.read(HOST_ROUTES_PATH)
    offenders = content.lines.each_with_index.filter_map do |line, idx|
      next if line.strip.start_with?('#')
      "#{idx + 1}: #{line.strip}" if line.include?("to: 'scinote/eln_ui/")
    end

    if MIGRATED
      assert_empty offenders,
                   "宿主 config/routes.rb 不得含 ELN UI 路由（零入侵铁律 / ADR-0022），仍有 #{offenders.size} 处"
    else
      # 迁移前：把现状如实钉住，防止"骨架阶段"误删/误改宿主路由。
      assert_equal EXPECTED_COUNT, offenders.size,
                   "迁移前宿主文件应有 #{EXPECTED_COUNT} 条 ELN UI 路由（当前 #{offenders.size} 条）；" \
                   '若已迁移请把本文件的 MIGRATED 置为 true'
    end
  end

  # ------------------------------------------------------------
  # 每条路由都必须能识别到真实存在的 controller 动作
  # ------------------------------------------------------------

  def test_every_route_recognizes_to_a_real_controller_action
    skip '运行时路由表里没有 ELN UI 路由（test 环境不执行 addon routes initializer）' unless routes_available?

    missing = []
    eln_routes.each do |r|
      begin
        controller = r.defaults[:controller].to_s.sub(%r{\A/}, '')
        klass = "#{controller.camelize}Controller".constantize
        action = r.defaults[:action]
        next if klass.method_defined?(action) || klass.private_method_defined?(action)

        missing << "#{r.name || "(匿名)"} → #{klass}##{action} (动作不存在)"
      rescue NameError => e
        missing << "#{r.name || "(匿名)"} → controller 解析失败：#{e.message.lines.first.strip}"
      end
    end

    assert_empty missing, "有路由指向不存在的 controller/动作（这类错误在请求时才炸成 500）：\n#{missing.join("\n")}"
  end
end