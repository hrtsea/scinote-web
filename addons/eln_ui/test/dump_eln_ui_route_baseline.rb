# frozen_string_literal: true

# ELN UI —— 路由基线生成器（一次性脚本，产物随库入库）
#
# 用法（容器内，**必须生产/开发环境 + root**）：
#   docker exec -u root scinote_web_production sh -c \
#     'cd /usr/src/app && bundle exec rails runner addons/eln_ui/test/dump_eln_ui_route_baseline.rb'
#
# 为什么需要它：基线里的路由三元组若靠人手誊抄，誊抄本身就是新的错误来源。
# 本脚本从**真实路由表**取样，产物写入 test/fixtures/eln_ui_routes_baseline.json。
#
# 🔴 什么时候该重跑：**只有**在「有意改动 ELN UI 的路由集合」时才重跑，
#    且必须与代码改动同一个提交，让基线变更本身进入 review视野。
#
# 🔴🔴 两个踩过的坑（2026-10-13 重跑时才炸出来）：
#   1. **不能按 controller 前缀 `scinote/eln_ui/` 过滤**。engine 声明
#      `isolate_namespace` 后，引擎侧 route set 的 defaults[:controller] 是**不带
#      前缀的裸名**（project_detail），宿主 mount 展开后也一样 ⇒ 按前缀过滤
#      在任何环境都只得 0 条。这份脚本自路由迁移（2026-10-12）后就没成功重跑过，
#      一直输出的是迁移前的旧产物。正解见下：按**控制器裸名白名单**认路，
#      与守卫 test/eln_ui_route_baseline_test.rb 的 ENGINE_CONTROLLERS 同源。
#   2. **RAILS_ENV=test 取不到引擎路由**（addon 的 routes initializer 只在服务
#      进程启动时跑，独立 runner 里 Engine.routes = 0 条、app routes 也不展开）
#      ⇒ 必须生产/开发环境跑。且容器内非 root 写不了 fixtures 目录
#      （宿主 mount 文件属主是宿主用户）⇒ 必须 `-u root`。
#
# ⚠ 幂等：同一份代码跑两次，输出逐字相同（内部排序已消除取样顺序的不确定性）。

require 'json'
require 'fileutils'

# 与 test/eln_ui_route_baseline_test.rb 的 ENGINE_CONTROLLERS 保持同一份口径
# （裸名，不带命名空间前缀）。⚠ 不含 workbench —— ADR-0045：其路由虽在 eln_ui，
# 但不计入本基线（白名单有意排除）。
ENGINE_CONTROLLERS = %w[
  project_detail project_list res_center res_apply_detail res_apply_action
  res_apply_create exp_detail my_module_detail project_approvers
  task_close_action notifications
].freeze

OUT = Rails.root.join('addons/eln_ui/test/fixtures/eln_ui_routes_baseline.json')

# 两处都扫：宿主路由表（mount 展开态）+ 引擎自己的 route set（runner 进程里
# Engine.routes 有货而 app routes 可能未展开，见坑 2）。按 [name, path, verb] 去重。
# 🔴 坑 3（2026-10-13）：`RouteSet#routes` 返回的是 **ActionDispatch::Journey::Routes**
#   （不是 Array）——`is_a?(Array)` 恒 false，早期写法让 engine_routes 恒等于 []，
#    silently 只剩 app routes 一路（test 环境下也是 0 条）。必须 `.to_a`。
#   守卫 test/eln_ui_route_baseline_test.rb#eln_routes 有同一处写法，同样已修。
engine_routes = begin
  r = Scinote::ElnUi::Engine.routes
  r.respond_to?(:routes) ? r.routes.to_a : []
rescue StandardError
  []
end

routes = (Rails.application.routes.routes.to_a + engine_routes).select do |r|
  bare = r.defaults[:controller].to_s.split('/').last.to_s
  ENGINE_CONTROLLERS.include?(bare)
end.uniq { |r| [r.name, r.path.spec.to_s, r.verb.to_s] }

triples = routes.map do |r|
  verbs = r.verb.to_s.split('|').reject { |v| v.empty? || v.start_with?('(.:') }.sort
  path = r.path.spec.to_s.sub(/\(\.:format\)\z/, '')
  helper = r.name
  key = helper || "ANON:#{verbs.join(',')}:#{path}:#{r.defaults[:controller]}##{r.defaults[:action]}"

  {
    'verb' => verbs.join(','),
    'path' => path,
    'key' => key,
    'controller' => "#{r.defaults[:controller]}##{r.defaults[:action]}"
  }
end.sort_by { |h| [h['path'], h['verb']] }

payload = {
  'generated_for' => 'eln_ui 路由自注册迁移（.scratch/eln-ui-route-self-registration）；' \
                     '2026-10-13 重生成：新增必传文档上传端点（ADR-0049）+ 修复 isolate_namespace 后取样失效',
  'controller_whitelist' => ENGINE_CONTROLLERS,
  'count' => triples.size,
  'named_count' => routes.count { |r| r.name },
  'anonymous_count' => routes.count { |r| !r.name },
  'routes' => triples
}

FileUtils.mkdir_p(File.dirname(OUT))
File.write(OUT, JSON.pretty_generate(payload) + "\n")

puts "WROTE #{OUT} count=#{triples.size} named=#{payload['named_count']} anon=#{payload['anonymous_count']}"
