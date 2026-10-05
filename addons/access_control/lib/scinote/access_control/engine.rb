# frozen_string_literal: true

require 'scinote/access_control'

module Scinote
  module AccessControl
    class Engine < ::Rails::Engine
      engine_name 'scinote_access_control'
      isolate_namespace Scinote::AccessControl

      # 装饰器自动加载（参考 esignatures / project_insights）
      config.to_prepare do
        Dir.glob(Engine.root.join('app', 'decorators', '**', '*_decorator.rb')).each do |path|
          ::Rails.configuration.cache_classes ? require(path) : load(path)
        end
      end

      # 把 addon 的迁移挂进宿主的迁移路径（仿 ai_eln / i18n）。
      # 没有这段的话 addon 的 db/migrate 不会被 rails db:migrate 看到。
      initializer :append_migrations do |app|
        unless app.root.to_s.match(root.to_s)
          config.paths['db/migrate'].expanded.each do |path|
            app.config.paths['db/migrate'] << path
          end
        end
      end

      # 页面模板所在目录（addon 的 app/views 已默认在 view path 里，这里显式声明避免歧义）
      initializer 'scinote_access_control.view_paths' do |app|
        app.config.paths['app/views'] << Engine.root.join('app', 'views').to_s
      end
    end
  end
end