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
      # label_printers_controller, specs) calls `addons_path` / `update_addon_path`
      # directly. Promote those three to host level (delegate to the engine proxy)
      # so the references and the `respond_to?(:addons_path)` graceful-disable
      # guards keep working while the engine stays isolated.
      config.to_prepare do
        Rails.application.routes.url_helpers.module_eval do
          define_method(:addons_path) do
            Scinote::AddonSettings::Engine.routes.url_helpers.addons_path
          end
          define_method(:edit_addon_path) do |*args|
            Scinote::AddonSettings::Engine.routes.url_helpers.edit_addon_path(*args)
          end
          define_method(:update_addon_path) do |*args|
            Scinote::AddonSettings::Engine.routes.url_helpers.update_addon_path(*args)
          end
        end
      end
    end
  end
end
