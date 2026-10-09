# frozen_string_literal: true

# AI 协议解析 addon —— 测试基础设施
#
# 跑法（容器内）：
#   RAILS_ENV=test bin/rails runner addons/ai_protocols/test/run.rb
# 或在宿主机一把梭：
#   ./run_ai_protocols_tests.sh
#
# ## 为什么复用 access_control 的 test_helper
#   与 eln_ui / workbench 同源理由：要建的是同一套场景（Team + User + UserRole +
#   UserAssignment），access_control 的工厂（make_team! / build_scene! / join_team! 等）
#   已经把坑踩平了 ——Team 必须带 created_by、团队 membership 是 assignable_type='Team'
#   的 UserAssignment（本仓**没有 user_teams 表**）、permission_granted? 以
#   user.current_team 为作用域不设就恒 false……
#
# ## ⚠ 本 addon 的 spec/ 目录**在本仓现用的生产容器里跑不起来**
#   （✅ 2026-10-09 实测，不是猜测）spec/ 下是 RSpec，而生产镜像 `.bundle/config` 里
#   `BUNDLE_WITHOUT: "development:test"` ⇒ 容器内**没有 rspec 可执行**
#   （`bundle exec rspec` → `command not found`），宿主 boot 日志也会打
#   `[SciNote] Unable to load specs from addons!`。
#   本仓 addon 的既定约定是 minitest + run.rb（eln_ui / access_control / workbench
#   三家都是，且都在被 run_*_tests.sh 真的跑），所以新增护栏一律写在本目录，
#   spec/ 那份属于历史遗留，不与本目录混用。

require_relative '../../access_control/test/test_helper'
