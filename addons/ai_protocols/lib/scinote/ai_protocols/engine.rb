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

      # 把 addon 的迁移挂进宿主的迁移路径（仿 access_control / ai_eln）。
      # 没有这段的话 addon 的 db/migrate 不会被 `rails db:migrate` 看到，
      # 新表（ai_parse_jobs）永远不会被建出来。
      initializer :append_migrations do |app|
        # String#match 会把参数当 Regexp（路径里的 "." 就是通配符），这里只是比前缀。
        unless app.root.to_s.start_with?(root.to_s)
          config.paths['db/migrate'].expanded.each do |path|
            app.config.paths['db/migrate'] << path
          end
        end
      end

      # 前端资产登记（仿 eln_ui）。
      # 🔴 生产 `config.assets.compile=false` ⇒ javascript_include_tag 走 Sprockets manifest，
      #   webpack 产物必须登记进 assets.precompile，否则 AssetNotFound 整页 500。
      initializer 'scinote_ai_protocols.assets' do |app|
        next unless app.config.respond_to?(:assets)

        app.config.assets.precompile += %w[ai_protocol_parser.js ai_protocol_parser.css]
      end

      # Self-register routes on the host app root. The addon is fully
      # self-contained: no `mount` line lives in the host's config/routes.rb,
      # so commenting the addon out of the Gemfile never breaks Rails boot.
      initializer 'scinote_ai_protocols.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::AiProtocols::Engine => '/'
        end
      end
    end
  end

  # activeagent 全局注册了 acronym "AI" ⇒ 路由层 camelize('ai_protocols') => 'AIProtocols'，
  # 与本 addon 真实模块 Scinote::AiProtocols（autoloader inflector 同样映射 ai_protocols => AiProtocols）不符，
  # 路由会按 Scinote::AIProtocols::ProtocolGeneratorController 查找控制器而失败。
  # 将 AIProtocols 别名到真实模块，零副作用地让路由解析命中（宿主 inflections.rb 只修了 autoloader，没修 router）。
  AIProtocols = AiProtocols
end
