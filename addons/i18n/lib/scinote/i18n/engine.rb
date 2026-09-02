module Scinote
  module I18n
    class Engine < ::Rails::Engine
      engine_name 'scinote_i18n'
      isolate_namespace Scinote::I18n
      paths['app/views'] << 'app/views/scinote/i18n'

      # Precompile engine-specific assets
      initializer 'scinote_i18n.assets.precompile' do |app|
        app.config.assets.precompile += %w(
          scinote/i18n/application.js
        )
      end

      # Merge localization files from engine
      initializer :load_localization do |app|
        app.config.i18n.load_path += Dir[
          ::Rails.root.join('addons', 'i18n', 'config', 'locales', '*.{rb,yml}')
        ]
      end

      # Configure available locales and fallbacks (missing keys fall back to en)
      initializer 'scinote_i18n.locales' do |_app|
        ::I18n.available_locales = Scinote::I18n.available_locales
        ::I18n.fallbacks = ::I18n::Locale::Fallbacks.new
        Scinote::I18n.available_locales.each do |locale|
          next if locale == :en

          ::I18n.fallbacks.map(locale => [:en])
        end
      end

      # Let i18n-js export ALL available locales (with en fallback merge)
      # into the frontend translations asset
      initializer 'scinote_i18n.i18n_js' do |_app|
        ::I18n::JS.config_file_path = Engine.root.join('config', 'i18n-js.yml')
      end

      # Initialize decorators
      config.to_prepare do
        Dir.glob(Engine.root.join('app',
                                  'decorators',
                                  '**',
                                  '*_decorator*.rb')) do |c|
          ::Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end

      # Self-register routes on the host app root. The addon is fully
      # self-contained: no `mount` line lives in the host's config/routes.rb,
      # so commenting the addon out of the Gemfile never breaks Rails boot.
      initializer 'scinote_i18n.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::I18n::Engine => '/'
        end
      end
    end
  end
end
