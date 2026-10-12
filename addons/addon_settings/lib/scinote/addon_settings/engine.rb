# frozen_string_literal: true

module Scinote
  module AddonSettings
    class Engine < ::Rails::Engine
      engine_name 'scinote_addon_settings'
      isolate_namespace Scinote::AddonSettings

      # Load this addon's own locale files.
      initializer 'scinote_addon_settings.locales' do |app|
        app.config.i18n.load_path += Dir[
          ::Rails.root.join('addons/addon_settings/config/locales/*.{rb,yml}')
        ]
      end

      # Register this engine's routes on the host root (isolate_namespace + mount)
      # so the host's config/routes.rb stays untouched — zero-intrusion at the
      # routing layer.
      #
      # NOTE: addon_settings is the management UI + discovery registry for *all*
      # other addons and declares `toggleable? => false` (lib/scinote/addon_settings.rb):
      # infrastructure that must stay enabled. Do NOT disable it by commenting it
      # out of the Gemfile in production. A removal is boot-safe (routes go
      # unregistered, pages 404 via the host's `respond_to?(:addons_path)` guards)
      # but it strips the ability to manage every other addon's configuration.
      initializer 'scinote_addon_settings.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::AddonSettings::Engine => '/'
        end
      end

      # Keep addon configuration secrets (API keys, tokens, etc.) out of request
      # logs. The host's filter_parameters covers :secret/:token but not the
      # arbitrary config keys addons declare (e.g. `api_key`), so filter the whole
      # `configuration` param. This is host-config-level hardening applied from the
      # addon — it touches no host routes or business code.
      initializer 'scinote_addon_settings.filter_parameters', after: :load_config_initializers do |app|
        app.config.filter_parameters += [:configuration]
      end

      # Expose this engine's own migrations so the addon_settings table is created
      # via `rails db:migrate` without touching the host's db/migrate
      # (zero-intrusion: migrations stay self-contained — see the routes
      # initializer NOTE on why this addon must stay enabled).
      initializer :append_migrations, after: :append_migrations do |app|
        next if app.root.to_s == root.to_s

        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
        end
      end

      # Isolated engines expose named routes only via the engine proxy, not as
      # host-level helpers, yet host code (sidebar, navigations_controller,
      # label_printers_controller, specs) calls `addons_path` / `edit_addon_path`
      # / `update_addon_path` directly and gates them behind
      # `respond_to?(:addons_path)` graceful-disable guards. Promote those three
      # to host level so the references and the guards keep working while the
      # engine stays isolated.
      #
      # 🔴 必须用「具体 define_method」把三个 helper **真定义**出来，不能用
      #   `method_missing` + `respond_to_missing?`（eln_ui 范本的写法）：
      #   宿主 navigations_controller / _sidebar / label_printers_controller
      #   用 `respond_to?(:addons_path)` 守卫兜底，而 Rails 的 route helper
      #   模块重写了 `respond_to?` 且**不 consult `respond_to_missing?`**
      #   （容器实测：method_missing 装上去后 `respond_to?` 仍 false、调用
      #   NoMethodError；改成具体 define_method 后 `respond_to?` 才 true）。
      #   旧写法（to_prepare + 单点 define_method 到 url_helpers）还踩了
      #   "url_helpers 每次访问返回新实例" 的坑 ⇒ 装上即丢。本实现装在
      #   稳定的 `@path_helpers_module`（运行期真身）上，且 `_path`/`_url`
      #   都定义，保证守卫与调用都可用。
      #
      #   禁用本 addon（注释 Gemfile 行）时 engine.rb 根本不加载 ⇒ 转发不安装
      #   ⇒ `respond_to?(:addons_path)` 自然 false ⇒ 守卫自动 fallback，优雅
      #   禁用契约保持（见上方 routes initializer 的 NOTE）。
      ADDON_SETTINGS_ROUTE_HELPERS = %i[addons edit_addon update_addon].freeze

      def self.install_route_helpers!(app)
        helper_names = ADDON_SETTINGS_ROUTE_HELPERS

        # 稳定真身：named_routes 的 @path_helpers_module。运行期 controller/view
        # 的 helper 链经 url_helpers 的祖先 include 它；而 url_helpers 每次访问
        # 返回新实例、装上即丢，所以只以它为"调用面"顺带装、真正靠 ph 生效。
        path_helpers = app.routes.named_routes.instance_variable_get(:@path_helpers_module)

        %i[path_helpers_module url_helpers].each do |which|
          target = which == :path_helpers_module ? path_helpers : app.routes.url_helpers
          next if target.nil?

          target.module_eval do
            helper_names.each do |base|
              # 真定义（非 method_missing）⇒ respond_to? 才能返回 true；
              # 引擎 helper 懒取，避免捕获到被重建前的路由表。
              define_method(:"#{base}_path") do |*args, **kwargs, &block|
                Scinote::AddonSettings::Engine.routes.url_helpers
                  .public_send(:"#{base}_path", *args, **kwargs, &block)
              end
              define_method(:"#{base}_url") do |*args, **kwargs, &block|
                Scinote::AddonSettings::Engine.routes.url_helpers
                  .public_send(:"#{base}_url", *args, **kwargs, &block)
              end
            end
          end
        end
      end

      config.to_prepare do
        Scinote::AddonSettings::Engine.install_route_helpers!(Rails.application)
      end
    end
  end
end
