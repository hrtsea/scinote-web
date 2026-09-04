# frozen_string_literal: true

module Scinote
  module ProjectInsights
    class Engine < ::Rails::Engine
      engine_name 'scinote_project_insights'
      isolate_namespace Scinote::ProjectInsights

      # 在 config.to_prepare 中注册 widget：
      # 晚于 config/initializers/extends.rb 执行，确保
      # Extends::DEFAULT_DASHBOARD_CONFIGURATION 已定义；
      # 去重守卫防止开发环境代码重载时重复注册。
      config.to_prepare do
        # 加载 addon 的 decorator（覆盖/注入核心视图行为）。
        # 注意：addons/*/app/decorators 已被 autoloaders 显式忽略
        # （config/application.rb），故须在此手动加载，参照 esignatures addon。
        Dir.glob(Engine.root.join('app', 'decorators', '**', '*_decorator*.rb')) do |c|
          ::Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end

      # Self-register routes on the host app root. The addon is fully
      # self-contained: no `mount` line lives in the host's config/routes.rb,
      # so commenting the addon out of the Gemfile never breaks Rails boot.
      initializer 'scinote_project_insights.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::ProjectInsights::Engine => '/'
        end
      end
    end
  end
end
