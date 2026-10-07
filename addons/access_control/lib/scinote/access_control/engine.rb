# frozen_string_literal: true

require 'scinote/access_control'

module Scinote
  module AccessControl
    class Engine < ::Rails::Engine
      engine_name 'scinote_access_control'
      isolate_namespace Scinote::AccessControl

      # 路由自注册（ADR-0022 —— 宿主 config/routes.rb 零 addon 路由）：
      #   路由画在 addons/access_control/config/routes.rb 的 Engine.routes.draw 里，
      #   这里把 Engine 挂到宿主根，路径与 helper 名跟挂在宿主时完全一致。
      #
      # 两个坑（实测踩过，别再踩）：
      #   1. engine 里**不能**写 `namespace :access_permissions` —— isolate_namespace 已经
      #      带上了 scinote/access_control 前缀，namespace 再叠一层，controller 会变成
      #      scinote/access_control/access_permissions/visibility_matrix。症状极隐蔽：
      #      路由**匹配得上**，但 recognition 报 "references missing controller"。
      #      正解 `scope path: 'access_permissions'` + 显式 `as:`（只取 URL 前缀，不动模块）。
      #   2. 引擎 helper 不进宿主 url_helpers，宿主视图直调老名字会 NoMethodError；
      #      而 `url_helpers.include(Engine.routes.url_helpers)` 会 SystemStackError ——
      #      那个模块自带 `included` 钩子（route_set.rb:613~624）会 self.dup 再 include 一次，
      #      自套自直到爆栈，日志里只有一行 "Exiting"，看不出是哪个 addon。
      #      正解见下面：把转发方法定义进宿主自己的模块，不 include 引擎那个。
      initializer 'scinote_access_control.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::AccessControl::Engine => '/'
        end

        install_route_helpers!(app)
      end

      # 宿主视图直调的老 helper 名（app/views/experiments/index/_header.html.erb:23）。
      # 路由搬进 engine 之后这些名字只活在 Engine.routes.url_helpers 里，
      # 要在这边留一份转发，否则宿主一渲染就 NoMethodError。
      PATH_HELPERS = %i[
        access_permissions_project_visibility_matrix_path
        access_permissions_toggle_project_visibility_matrix_path
        access_permissions_project_visibility_strategy_path
        access_permissions_project_visibility_backfill_path
      ].freeze

      # 只 define_method 转发一层，**绝不** include 引擎那个 url_helpers 模块（坑 2）。
      # 转发而不是复制实现：路由形状改了，两边不用各改一遍。
      def install_route_helpers!(app)
        engine_helpers = Scinote::AccessControl::Engine.routes.url_helpers

        app.routes.url_helpers.module_eval do
          PATH_HELPERS.each do |helper_name|
            define_method(helper_name) do |*args, **kwargs, &block|
              engine_helpers.public_send(helper_name, *args, **kwargs, &block)
            end
          end
        end
      end

      # 装饰器自动加载（参考 esignatures / project_insights）
      config.to_prepare do
        Dir.glob(Engine.root.join('app', 'decorators', '**', '*_decorator.rb')).each do |path|
          ::Rails.configuration.cache_classes ? require(path) : load(path)
        end

        # 装饰加载完才能验：verify! 要看到 Experiment 上的 ac_manually_granted?。
        # 一次启动检查，换掉散在运行时各处的 respond_to? 探测（见 lib 里的说明）。
        Scinote::AccessControl.verify!
      end

      # 把 addon 的迁移挂进宿主的迁移路径（仿 ai_eln / i18n）。
      # 没有这段的话 addon 的 db/migrate 不会被 rails db:migrate 看到。
      initializer :append_migrations do |app|
        # String#match 会把参数当 Regexp（路径里的 "." 就是通配符），这里只是比前缀。
        unless app.root.to_s.start_with?(root.to_s)
          config.paths['db/migrate'].expanded.each do |path|
            app.config.paths['db/migrate'] << path
          end
        end
      end

    end
  end
end