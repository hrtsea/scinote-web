require_relative 'configuration'

module Scinote
  module WechatGateway
    class Engine < ::Rails::Engine
      engine_name 'scinote_wechat_gateway'
      isolate_namespace Scinote::WechatGateway

      # 读凭证 + enabled 开关（声明在 routes 之前，确保 routes 看到正确开关）
      initializer 'scinote_wechat_gateway.config' do |app|
        cfg = Scinote::WechatGateway.configuration
        cfg.enabled = ENV.fetch('WECHAT_GATEWAY_ENABLED', 'true') != 'false'
        cfg.wecom_token = ENV['WECOM_TOKEN']
        cfg.wecom_encoding_aes_key = ENV['WECOM_ENCODING_AES_KEY']
        cfg.wecom_corpid = ENV['WECOM_CORPID']
        cfg.ilink_token = ENV['ILINK_TOKEN']
        cfg.ilink_base_url = ENV['ILINK_BASE_URL']
        # 把企微凭证喂给 WecomCrypto（仅启用时）
        if cfg.enabled
          Scinote::WechatGateway::WecomCrypto.config = {
            token: cfg.wecom_token,
            encoding_aes_key: cfg.wecom_encoding_aes_key,
            receive_id: cfg.wecom_corpid
          }
        end
      end

      # 路由自注册（零入侵：宿主 config/routes.rb 不动）；disabled 时不挂载
      initializer 'scinote_wechat_gateway.routes' do |app|
        next unless Scinote::WechatGateway.enabled?
        app.routes.append do
          mount Scinote::WechatGateway::Engine => '/wechat_gateway'
        end
      end

      initializer 'scinote_wechat_gateway.assets.precompile' do |app|
        app.config.assets.precompile += %w()
      end

      initializer :static_assets do |app|
        app.middleware.insert_before(
          ::ActionDispatch::Static,
          ::ActionDispatch::Static,
          "#{root}/public"
        )
      end

      initializer :load_localization do |app|
        app.config.i18n.load_path += Dir[
          Rails.root.join('addons', 'wechat_gateway', 'config', 'locales', '*.{rb,yml}')
        ]
      end

      initializer :append_migrations do |app|
        unless app.root.to_s.match(root.to_s)
          config.paths['db/migrate'].expanded.each do |p|
            app.config.paths['db/migrate'] << p
          end
        end
      end

      config.to_prepare do
        Dir.glob(Engine.root.join('app', 'decorators', '**', '*_decorator*.rb')) do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end
    end
  end
end
