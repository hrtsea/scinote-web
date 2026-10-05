# frozen_string_literal: true
#
# 跑法（容器内）：
#   RAILS_ENV=test bin/rails runner addons/workbench/test/run.rb
#
# ⚠ 与 access_control / eln_ui 同款：prepare! 加列 + 建角色，幂等可重复。

require_relative 'test_helper'

AcTest.prepare!

Dir[File.expand_path('*_test.rb', __dir__)].sort.each { |f| require f }
