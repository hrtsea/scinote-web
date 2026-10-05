# frozen_string_literal: true

# 工作台 addon —— 测试基础设施
#
# ## 为什么直接复用 access_control 的 test_helper
#   与 eln_ui 同源理由：两边要建的是**同一套场景**（Team + User + Project +
#   Experiment + MyModule + UserAssignment），access_control 的工厂（make_team! /
#   build_scene! / make_task! 等）已经把这些坑都踩平了（Team 必须带 created_by、
#   UA 走 assignable 而不是 user_teams 表、test 环境 job 只入队不执行要显式
#   perform_now …）。为工作台再抄一份 = 把同一批坑重踩一遍。
#
# ## 跑法（容器内）
#   RAILS_ENV=test bin/rails runner addons/workbench/test/run.rb
#
# ⚠ 本目录没有也不需要 eln_ui_factories：工作台只读业务库，资源申请/消耗明细
#   这两张二开表在测试里用各用例内的私有工厂现场建（见 workbench_test.rb）。

require_relative '../../access_control/test/test_helper'
