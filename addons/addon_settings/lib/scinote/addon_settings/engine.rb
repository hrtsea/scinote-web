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

      # Self-register routes on the host app root via mount, mirroring the other
      # addons (ai_protocols, esignatures, …): isolate_namespace + mount. The
      # addon is fully self-contained — no `mount` line lives in the host's
      # config/routes.rb, so commenting the addon out of the Gemfile never breaks
      # Rails boot (the routes simply are not registered and the pages 404
      # instead of crashing the boot).
      initializer 'scinote_addon_settings.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::AddonSettings::Engine => '/'
        end
      end

      # Expose this engine's own migrations to the host so the addon_settings
      # table is created via `rails db:migrate` without ever touching the host's
      # db/migrate (zero-intrusion: the addon stays fully self-contained and is
      # removable via the Gemfile alone).
      initializer :append_migrations, after: :append_migrations do |app|
        next if app.root.to_s == root.to_s

        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
        end
      end

      # Mounted engines (even isolated ones) only expose their named routes via
      # the engine proxy (`Engine.routes.url_helpers`), never as host-level
      # helpers. This addon's host code (sidebar, navigations_controller,
      # label_printers_controller) and its request specs call `addons_path` /
      # `update_addon_path` directly, so we promote those two helpers to the host
      # level by delegating to the engine proxy. This keeps the host references
      # and the graceful-disable `respond_to?(:addons_path)` guards working
      # unchanged while the engine itself stays isolated + mounted like the other
      # addons.
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
