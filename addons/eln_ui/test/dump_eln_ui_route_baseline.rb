# frozen_string_literal: true
#
# ELN UI —— 路由基线生成器（一次性脚本，产物随库入库）
#
# 用法（容器内）：
#   RAILS_ENV=test bin/rails runner addons/eln_ui/test/dump_eln_ui_route_baseline.rb
#
# 为什么需要它：基线里的 30 条三元组若靠人手誊抄，誊抄本身就是新的错误来源。
# 本脚本从**真实路由表**取样，产物写入 test/fixtures/eln_ui_routes_baseline.json。
#
# 🔴 什么时候该重跑：**只有**在「有意改动 ELN UI 的路由集合」时才重跑，
#    且必须与代码改动同一个提交，让基线变更本身进入 review视野。
#    迁移（ticket 02）**不改**路由集合，所以那一步不需要重跑 —— 这正是基线的作用：
#    证明迁移只换了注册位置，没换路由本身。
#
# ⚠ 幂等：同一份代码跑两次，输出逐字相同（内部排序已消除取样顺序的不确定性）。

require 'json'
require 'fileutils'

ELN_CONTROLLER_PREFIX = 'scinote/eln_ui/'.freeze
OUT = Rails.root.join('addons/eln_ui/test/fixtures/eln_ui_routes_baseline.json')

routes = Rails.application.routes.routes.select do |r|
  r.defaults[:controller].to_s.include?(ELN_CONTROLLER_PREFIX)
end

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
  'generated_for' => 'eln_ui 路由自注册迁移（.scratch/eln-ui-route-self-registration）',
  'controller_prefix' => ELN_CONTROLLER_PREFIX,
  'count' => triples.size,
  'named_count' => routes.count { |r| r.name },
  'anonymous_count' => routes.count { |r| !r.name },
  'routes' => triples
}

FileUtils.mkdir_p(File.dirname(OUT))
File.write(OUT, JSON.pretty_generate(payload) + "\n")

puts "WROTE #{OUT} count=#{triples.size} named=#{payload['named_count']} anon=#{payload['anonymous_count']}"