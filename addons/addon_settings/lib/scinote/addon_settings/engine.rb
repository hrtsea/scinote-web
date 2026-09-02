# frozen_string_literal: true

module Scinote
  module AddonSettings
    class Engine < ::Rails::Engine
      engine_name 'scinote_addon_settings'

      # Load this addon's own locale files.
      initializer 'scinote_addon_settings.locales' do |app|
        app.config.i18n.load_path += Dir[
          ::Rails.root.join('addons/addon_settings/config/locales/*.{rb,yml}')
        ]
      end

      # Self-register the settings page routes on the host app root.
      # No `get`/`put` line lives in the host's config/routes.rb, so commenting
      # this addon out of the Gemfile never breaks Rails boot (the routes simply
      # are not registered and the pages 404 instead of crashing the boot).
      initializer 'scinote_addon_settings.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::AddonSettings::Engine => '/'
        end
      end
    end
  end
end
