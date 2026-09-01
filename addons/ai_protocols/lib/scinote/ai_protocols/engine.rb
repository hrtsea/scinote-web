# frozen_string_literal: true

module Scinote
  module AiProtocols
    class Engine < ::Rails::Engine
      engine_name 'scinote_ai_protocols'
      isolate_namespace Scinote::AiProtocols

      # canaid discovers addon permissions by scanning each engine's
      # `eager_load_paths` for a directory ending in `permissions` (see
      # config/initializers/canaid.rb). Rails engines' `app/permissions` is
      # autoloaded but NOT part of `eager_load_paths` by default, so the
      # permissions directory has to be registered explicitly.
      config.eager_load_paths << root.join('app', 'permissions').to_s

      # Load deface view overrides (surgical injections into host views) from
      # app/overrides. deface auto-discovers these for the host app, but engine
      # overrides are loaded explicitly so they register reliably across dev
      # reload and the test environment.
      config.to_prepare do
        Dir.glob(Engine.root.join('app', 'overrides', '**', '*.rb')).sort.each do |override|
          ::Rails.configuration.cache_classes ? require(override) : load(override)
        end
      end
    end
  end
end
