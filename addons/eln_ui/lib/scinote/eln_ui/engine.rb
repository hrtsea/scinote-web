# frozen_string_literal: true

module Scinote
  module ElnUi
    class Engine < ::Rails::Engine
      engine_name 'scinote_eln_ui'
      isolate_namespace Scinote::ElnUi

      # 装饰器自动加载（照抄 access_control / esignatures 的先例）：
      # app/decorators/**/*_decorator.rb 里对原生模型做 prepend 扩展
      # （如任务消耗快照单价 —— SCN-RES-COST-2）。
      config.to_prepare do
        Dir.glob(Engine.root.join('app', 'decorators', '**', '*_decorator.rb')).each do |path|
          ::Rails.configuration.cache_classes ? require(path) : load(path)
        end
      end

      # Vue3 原型构建产物（ELN系统-Vue3/dist-embed）落在本 addon 的 app/assets 下，
      # 生产需要显式登记进 precompile，否则 javascript_include_tag / asset_path 解析不到。
      # 产物是**构建生成**的（不是源码），所以走 bundle 构建流程更新，别手改这两个文件。
      initializer 'scinote_eln_ui.assets' do |app|
        next unless app.config.respond_to?(:assets)

        # 四页各一份 js/css：vite lib 模式一个 config 只能挂一个 entry，
        # 所以任务页第四份 bundle 也要单独登记（少登记 = 页面 AssetNotFound 500）。
        # ⚠ CSS 一律**改名落地**（eln_task_detail.css），同名产物会互相覆盖
        #   —— 实测过同一份 eln-system-vue3.css 被后打的页面换血。
        app.config.assets.precompile += %w[
          eln_vue3/eln_project_detail.js
          eln_vue3/eln-system-vue3.css
          eln_vue3/eln_project_list.js
          eln_vue3/eln_project_list.css
          eln_vue3/eln_exp_detail.js
          eln_vue3/eln_exp_detail.css
          eln_vue3/eln_task_detail.js
          eln_vue3/eln_task_detail.css
          eln_vue3/eln_res_center.js
          eln_vue3/eln_res_center.css
          eln_vue3/eln_apply_detail.js
          eln_vue3/eln_apply_detail.css
        ]
      end
    end
  end
end
