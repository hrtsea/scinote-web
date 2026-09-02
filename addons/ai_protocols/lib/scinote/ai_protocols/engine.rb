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
        # Load addon decorators (view/helper extensions) in dev/reload, mirroring
        # the esignatures addon. This is what exposes `can_generate_protocol_with_ai?`
        # to core views (e.g. protocols/index) so the AI create-button override
        # does not raise NoMethodError at render time.
        Dir.glob(Engine.root.join('app', 'decorators', '**', '*_decorator*.rb')).sort.each do |decorator|
          ::Rails.configuration.cache_classes ? require(decorator) : load(decorator)
        end
      end

      # Self-register routes on the host app root. The addon is fully
      # self-contained: no `mount` line lives in the host's config/routes.rb,
      # so commenting the addon out of the Gemfile never breaks Rails boot.
      initializer 'scinote_ai_protocols.routes' do |app|
        app.routes.append do
          mount Scinote::AiProtocols::Engine => '/'
        end
      end
    end
  end
end
