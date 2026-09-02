# frozen_string_literal: true

module Scinote
  module Esignatures
    class Engine < ::Rails::Engine
      engine_name 'scinote_esignatures'
      isolate_namespace Scinote::Esignatures

      # canaid discovers addon permissions by scanning each engine's
      # `eager_load_paths` for a directory ending in `permissions` (see
      # config/initializers/canaid.rb). Engine `app/*` subdirectories are
      # autoloaded but are NOT part of `eager_load_paths` by default, so the
      # permissions directory has to be registered explicitly.
      config.eager_load_paths << root.join('app', 'permissions').to_s

      # Load addon decorators (overrides of core views/behaviour) in dev/reload.
      config.to_prepare do
        Dir.glob(Engine.root.join('app', 'decorators', '**', '*_decorator*.rb')) do |c|
          ::Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end

      # Self-register routes on the host app root. The addon is fully
      # self-contained: no `mount` line lives in the host's config/routes.rb,
      # so commenting the addon out of the Gemfile never breaks Rails boot.
      initializer 'scinote_esignatures.routes' do |app|
        app.routes.append do
          mount Scinote::Esignatures::Engine => '/'
        end
      end
    end
  end
end
