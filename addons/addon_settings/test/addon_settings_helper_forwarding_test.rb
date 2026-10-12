# frozen_string_literal: true
#
# addon_settings helper 转发守卫（轻量，不依赖 DB）
#
# ## 守的是什么
# addon_settings 是 isolate_namespace 引擎，其具名路由 helper（`addons_path` /
# `edit_addon_path` / `update_addon_path`）只活在 `Engine.routes.url_helpers` 上，
# 宿主 navigations_controller / _sidebar / label_printers_controller 用
# `respond_to?(:addons_path)` 守卫兜底，并直接调用这三个 helper。
#
# engine.rb 必须把转发**具体 define_method** 到宿主 url_helpers（@path_helpers_module
# 真身），否则：
#   · 旧写法（to_prepare + 单点 define_method 到 url_helpers）⇒ 方法装在每次访问
#     返回新实例的 url_helpers 上，装上即丢；
#   · method_missing + respond_to_missing?（eln_ui 范本）⇒ Rails 的 route helper
#     模块重写 respond_to? 且不 consult respond_to_missing? ⇒ respond_to? 恒 false，
#     宿主守卫永远走 fallback，用户设置里的 "Addons" 入口静默消失。
# 详见 ADR 待补（addon_settings helper 转发修复）。
#
# ## 本守卫
# 1. 静态漂移检查：engine.rb 的 ADDON_SETTINGS_ROUTE_HELPERS 必须与 config/routes.rb
#    的 `as:` 名完全一致（少一个/错一个 ⇒ 对应页面 helper 缺失，运行期才炸且难回溯）。
# 2. 运行期检查（仅当 addon 路由已绘制的服务进程里跑，如生产容器；RAILS_ENV=test
#    下 Engine.routes 为 0 条，自动 skip）：断言宿主消费对象 respond_to?(:addons_path)
#    为 true 且 addons_path 返回正确路径。

require 'minitest/autorun'

class AddonSettingsHelperForwardingTest < Minitest::Test
  ENGINE_RB = File.expand_path('../lib/scinote/addon_settings/engine.rb', __dir__).freeze
  ROUTES_RB = File.expand_path('../config/routes.rb', __dir__).freeze

  def test_forwarding_list_matches_route_as_names
    route_bases = File.read(ROUTES_RB)
                    .scan(/as:\s*:([a-z_]+)/)
                    .flatten
                    .map(&:to_sym)
                    .sort

    engine_src = File.read(ENGINE_RB)
    const = engine_src[/ADDON_SETTINGS_ROUTE_HELPERS\s*=\s*%i\[([^\]]*)\]/, 1]
    flunk 'engine.rb 中未找到 ADDON_SETTINGS_ROUTE_HELPERS 常量' if const.nil?

    helper_bases = const.scan(/[a-z_]+/).map(&:to_sym).sort

    assert_equal route_bases, helper_bases,
                 "转发清单与 routes.rb 的 as: 名不一致（漂移 ⇒ 某页面 helper 缺失）"
  end

  def test_runtime_forwarding_when_routes_drawn
    unless defined?(Rails) && defined?(Scinote::AddonSettings::Engine)
      skip('Rails/Engine 未加载，跳过运行期断言')
    end
    engine_helpers = Scinote::AddonSettings::Engine.routes.url_helpers
    skip('addon_settings 路由未绘制（非服务进程），运行期断言跳过') \
      unless engine_helpers.respond_to?(:addons_path)

    o = Object.new
    o.extend(Rails.application.routes.url_helpers)

    assert o.respond_to?(:addons_path),
           '宿主 url_helpers 必须 respond_to?(:addons_path)（守卫依赖它）'
    assert_equal '/users/settings/account/addons', o.addons_path

    assert o.respond_to?(:edit_addon_path)
    assert o.respond_to?(:update_addon_path)
  end
end
