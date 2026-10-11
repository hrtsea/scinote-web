# frozen_string_literal: true

module Scinote
  module Workbench
    class Engine < ::Rails::Engine
      engine_name 'scinote_workbench'
      isolate_namespace Scinote::Workbench

      # ⚠ 本 addon **没有 app/decorators**：工作台只读业务库，不 prepend 任何原生模型。
      #   （与 eln_ui 不同：eln_ui 的 MMR 单价快照装饰器是消耗链路需要的。）
      #   这里刻意**不**加载 app/decorators 的 glob —— 留空比留一段死代码好。

      # 路由自注册（ADR-0022 —— 宿主 config/routes.rb 零 addon 路由）：
      #   路由画在 addons/workbench/config/routes.rb 的 Engine.routes.draw 里，
      #   这里把引擎挂到宿主根；对外 URL（/eln_workbench）与 helper 名（eln_workbench）
      #   与当初挂在宿主时逐字一致。
      #
      # 为什么需要：迁移前这条路由寄生在宿主 config/routes.rb，⇒ 注释 Gemfile 里
      # `gem 'scinote_workbench'` 那行无法优雅禁用（宿主路由表会指向一个不再被
      # Bundler 加载的 controller）。挂上引擎后才拿回契约承诺的"禁用即下线、
      # 宿主照常启动"。
      #
      # `after: :add_routes` 为显式声明（ADR-0022 §决策 4）；`append` 保证 addon 路由
      # 排在宿主之后，addon 无法用同名路径覆盖核心路由。
      initializer 'scinote_workbench.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::Workbench::Engine => '/'
        end
      end

      # ℹ 本addon **不需要** helper 转发。engine 声明了 isolate_namespace 后，
      #   具名 helper 只活在 Engine.routes.url_helpers 上、不会自动进宿主 url_helpers——
      #   但 workbench 只有一条页面入口路由，宿主侧没有任何代码调 `eln_workbench_*_path`
      #   （视图侧只引assets，不产主动作 URL），实测无需转发即可工作。
      #   已卸载的 project_insights 是同一形态（自注册挂载 + 零转发），可作范本。
      #   ⚠ 若将来宿主开始调它的 helper，**必须用 method_missing 惰性转发**，
      #     不要用「启动期把方法塞进某模块」的写法——那种写法与 Rails 路由初始化
      #     时序赛跑，必失败（eln_ui 实测踩过三次：respond_to? 恒 false /
      #     被后续初始化冲掉且回报成功 / 生产只跑一次导致整页 500）。见 eln_ui engine.rb。

      # 工作台前端的 JS+CSS 已全部改为**宿主 webpack 构建**（entry: eln_workbench，
      # 真源在 eln_ui addon 的 app/javascript/vue/eln/，见 config/webpack/webpack.config.js）。
      # 产物输出到 app/assets/builds/eln_workbench.{js,css}，视图用
      #   javascript_include_tag 'eln_workbench' / stylesheet_link_tag 'eln_workbench' 引用。
      #
      # 🔴 生产 `config.assets.compile=false` ⇒ 这两个 tag 走 Sprockets manifest 解析，
      #   webpack 产物**必须**登记进 assets.precompile 才会被 fingerprint（否则整页 500）。
      #   旧的 vite 单独打包 blob（workbench_vue3/*）已删除。
      initializer 'scinote_workbench.assets' do |app|
        next unless app.config.respond_to?(:assets)

        app.config.assets.precompile += %w[
          eln_workbench.js eln_workbench.css
        ]
      end
    end
  end
end
