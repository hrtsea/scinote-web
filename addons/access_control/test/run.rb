# frozen_string_literal: true
#
# 跑法（容器内）：
#   RAILS_ENV=test bin/rails runner addons/access_control/test/run.rb
#
# 只跑某一个文件：
#   RAILS_ENV=test bin/rails runner addons/access_control/test/d2_visibility_strategy_test.rb

require_relative 'test_helper'

# 环境准备必须在事务外做：DDL（加列）不能回滚，角色/seed admin 也要活过单测事务。
AcTest.prepare!

Dir[File.expand_path('*_test.rb', __dir__)].sort.each { |f| require f }
