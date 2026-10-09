# frozen_string_literal: true

module Scinote
  module Workbench
    class Engine < ::Rails::Engine
      engine_name 'scinote_workbench'
      isolate_namespace Scinote::Workbench

      # ⚠ 本 addon **没有 app/decorators**：工作台只读业务库，不 prepend 任何原生模型。
      #   （与 eln_ui 不同：eln_ui 的 MMR 单价快照装饰器是消耗链路需要的。）
      #   这里刻意**不**加载 app/decorators 的 glob —— 留空比留一段死代码好。

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
