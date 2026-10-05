# frozen_string_literal: true

module Scinote
  module Workbench
    class Engine < ::Rails::Engine
      engine_name 'scinote_workbench'
      isolate_namespace Scinote::Workbench

      # ⚠ 本 addon **没有 app/decorators**：工作台只读业务库，不 prepend 任何原生模型。
      #   （与 eln_ui 不同：eln_ui 的 MMR 单价快照装饰器是消耗链路需要的。）
      #   这里刻意**不**加载 app/decorators 的 glob —— 留空比留一段死代码好。

      # Vue3 原型构建产物落在本 addon 的 app/assets 下，
      # 生产需要显式登记进 precompile，否则 asset_path / javascript_include_tag
      # 解析不到（与 eln_ui 同一套「precompile 名单精确匹配」机制）。
      initializer 'scinote_workbench.assets' do |app|
        next unless app.config.respond_to?(:assets)

        # ⚠ 一行一份 js/css：vite lib 模式一个 config 只挂一个 entry（见
        #   ELN系统-Vite3/vite.embed.wb.config.js），少登记 = 页面 AssetNotFound 500。
        #   CSS 也**改名落地**（eln_workbench.css），不与其他页共用同名产物。
        #   ⚠ 产物是**构建生成**的，走 sync_workbench.sh --BuildAssets --push 更新，
        #     别手改这两个文件。
        app.config.assets.precompile += %w[
          workbench_vue3/eln_workbench.js
          workbench_vue3/eln_workbench.css
        ]
      end
    end
  end
end
