# frozen_string_literal: true

# lib/ 不参与 Zeitwerk 自动加载，宿主模型解析模块须显式 require
require_relative "host_models"

module Scinote
  module AiEln
    class Engine < ::Rails::Engine
      engine_name 'scinote_ai_eln'
      isolate_namespace Scinote::AiEln
      paths['app/views'] << 'app/views/scinote/ai_eln'

      # 幂等：仅把配置挂到宿主 config 命名空间，不写 DB、不跑迁移
      initializer 'scinote_ai_eln.configuration', before: :load_config_initializers do
        config.scinote_ai_eln = Scinote::AiEln.configuration
      end

      # 路由自挂载（宿主契约 docs/development/addons-host-contract.md §5）：
      # 宿主 config/routes.rb 保持零 mount，引擎自行 append 挂载。
      # 故从 Gemfile 注释掉本 addon 时，宿主仍能正常 boot，仅本 addon 端点 404。
      # 仿 ai_protocols / esignatures 的实现。
      initializer 'scinote_ai_eln.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::AiEln::Engine => '/ai_eln'
        end
      end

      # Precompile engine-specific assets
      initializer 'scinote_ai_eln.assets.precompile' do |app|
        app.config.assets.precompile += %w(
        )
      end

      # Include static assets
      initializer :static_assets do |app|
        app.middleware.insert_before(
          ::ActionDispatch::Static,
          ::ActionDispatch::Static,
          "#{root}/public"
        )
      end

      # Merge localization files from engine
      initializer :load_localization do |app|
        app.config.i18n.load_path += Dir[
          Rails.root.join(
            'addons',
            'ai_eln',
            'config',
            'locales',
            '*.{rb,yml}'
          )
        ]
      end

      # Initialize migrations
      initializer :append_migrations do |app|
        unless app.root.to_s.match(root.to_s)
          config.paths['db/migrate'].expanded.each do |p|
            app.config.paths['db/migrate'] << p
          end
        end
      end

      # Initialize decorators
      config.to_prepare do
        Dir.glob(Engine.root.join('app',
                                  'decorators',
                                  '**',
                                  '*_decorator*.rb')) do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end
    end
  end
end
