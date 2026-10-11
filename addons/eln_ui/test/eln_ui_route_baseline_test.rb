# frozen_string_literal: true
#
# ELN UI —— 路由基线与迁移契约守卫（ticket 01 建立，ticket 02 用于验证迁移）
#
# ## 背景
# ELN UI 的 30 条路由当前寄生在宿主 `config/routes.rb`（违反零入侵铁律，见 ADR-0022）。
# 本文件在**任何路由被搬动之前**先把它们的「动词 + 路径 + helper 名」冻结成基线，
# 使"迁移有没有改坏东西"成为机器断言，而不是靠人工数 30 条路由。
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

  # 基线快照文件（由 `rake` 任务或 bin/rails runner 生成后随库入库）。
  # 首次生成见本文件末尾「如何重建基线」一节。
  BASELINE_PATH = File.expand_path('../test/fixtures/eln_ui_routes_baseline.json', __dir__)

  # 迁移后 ELN UI 路由应落在 addon 自己的路由定义里；宿主 routes.rb 不得再出现。
  HOST_ROUTES_PATH = Rails.root.join('config/routes.rb')

  EXPECTED_COUNT = 30

  def eln_routes
    Rails.application.routes.routes.select do |r|
      r.defaults[:controller].to_s.include?(ELN_CONTROLLER_PREFIX)
    end
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
  # ⚠ 这条断言在 ticket 01（骨架阶段）**必然为红**——路由此刻仍在宿主文件里，正是 01
  # 要求的"骨架不得改变现状"。它不是一条"应当现在就绿"的测试，而是给 ticket 02 留的
  # 锚点：迁移完成后它必须转绿，将来谁把路由挂回宿主它就再次变红。
  #
  # 为免它污染 01 的整体结果，这里把实测值断言成一个**可切换的期望**：
  # 迁移完成后把 MIGRATED 置为 true，这条就从"记录现状"变成"强制清零"。
  # 改动范围仅这一行，切换点显式可见，避免出现"悄悄把断言删掉"的退化。
  MIGRATED = false

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