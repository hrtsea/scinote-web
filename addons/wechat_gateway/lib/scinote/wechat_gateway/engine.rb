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
        cfg.default_project_id = ENV['WECHAT_GATEWAY_PROJECT_ID']
        cfg.vision_endpoint = ENV['VISION_ENDPOINT']
        cfg.ai_enabled = ENV.fetch('WECHAT_GATEWAY_AI_ENABLED', 'false') == 'true'
        cfg.ai_endpoint = ENV['AI_ENDPOINT']
        cfg.ai_api_key = ENV['AI_API_KEY']
        cfg.ai_model = ENV.fetch('AI_MODEL', 'deepseek-chat')
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

      # 写入层接线（Ticket 01）：已绑定用户消息经 Inbound.receive -> Intake.handle。
      # 默认 intake_handler 为 no-op（见 inbound.rb）；启用时替换为真实写入链路。
      initializer 'scinote_wechat_gateway.intake' do |app|
        next unless Scinote::WechatGateway.enabled?

        Scinote::WechatGateway::Inbound.intake_handler = lambda do |user_id, message|
          Scinote::WechatGateway::Intake.handle(
            user_id, message,
            # 群 @ 指派：把被 @ 的微信 userid 解析为已绑定的 SciNote 用户
            mention_resolver: lambda do |wechat_id, platform|
              Scinote::WechatGateway::Inbound.store.find_binding(wechat_id, platform)
            end,
            # 图片视觉识别（仅配置 VISION_ENDPOINT 时启用）
            vision_describer: (Scinote::WechatGateway::Vision.enabled? ? Scinote::WechatGateway::Vision.method(:describe) : nil),
            # AI 结构化抽取 + Formulation 落库（仅 WECHAT_GATEWAY_AI_ENABLED=true 且配置 AI_ENDPOINT 时启用）
            ai_llm: (Scinote::WechatGateway::AiProcessor.enabled? ? ->(text) { Scinote::WechatGateway::AiProcessor.extract(text) } : nil),
            formulation_writer: (Scinote::WechatGateway::AiProcessor.enabled? ? Scinote::WechatGateway::FormulationWriter.new : nil)
          )
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
