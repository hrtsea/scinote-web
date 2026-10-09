# frozen_string_literal: true
#
# 跑法（容器内）：
#   RAILS_ENV=test bin/rails runner addons/ai_protocols/test/run.rb
#
# ⚠ 与 access_control / eln_ui / workbench 同款：prepare! 建（幂等的）环境，
#   用例各自包在事务里跑完回滚。

require_relative 'test_helper'

AcTest.prepare!

Dir[File.expand_path('*_test.rb', __dir__)].sort.each { |f| require f }
