# frozen_string_literal: true
#
# 跑法（容器内）：
#   RAILS_ENV=test bin/rails runner addons/eln_ui/test/run.rb

require_relative 'test_helper'

AcTest.prepare!

Dir[File.expand_path('*_test.rb', __dir__)].sort.each { |f| require f }
