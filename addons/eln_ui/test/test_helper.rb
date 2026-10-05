# frozen_string_literal: true

# eln_ui addon —— 测试基础设施
#
# ## 为什么直接 require access_control 的 test_helper
#   两边要建的是**同一套场景**（Team + User + Project + Experiment + MyModule + UA），
#   而 access_control 里的工厂（make_team! / build_scene! / make_experiment! 等）已经把这些
#   坑都踩平了：Team 必须带 created_by、UA 走 assignable 而不是 user_teams 表、
#   test 环境 job 只入队不执行要显式 perform_now …
#   为 eln_ui 再抄一份 = 把同一批坑重新踩一遍，所以直接复用，elnu 测试只关心「数据装配」。
#
#   ⚠ 代价：跑 eln_ui 测试前先跑一次 access_control 的 run.rb（或同目录 run.rb），
#     两侧共用 `AcTest.prepare!`（加列 + 建角色 + seed admin），幂等可重复。

require_relative '../../access_control/test/test_helper'

# eln_ui 共享工厂（库存/流水/任务消耗造数）—— ResCenter 与项目详情测试共用，
# 工厂细节见 eln_ui_factories.rb 头注释。各测试类 `include ElnUiFactories`。
require_relative 'eln_ui_factories'
