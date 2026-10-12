# frozen_string_literal: true
#
# 跑法（测试容器，RAILS_ENV=test 且已 bundle install --with test）：
#   RAILS_ENV=test bin/rails runner addons/addon_settings/test/run.rb
#
# 跑法（生产容器，路由已绘制，运行期断言会真正执行）：
#   RAILS_ENV=production bundle exec rails runner addons/addon_settings/test/run.rb

require_relative 'addon_settings_helper_forwarding_test'
