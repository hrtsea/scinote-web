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

      # ELN UI 前端资产登记。
      #
      # 除项目列表页外，其余 5 页（res_center / project_detail / exp_detail / task_detail /
      # apply_detail；workbench 在 workbench addon 单独登记）的 JS+CSS 已全部改为
      # **宿主 webpack 构建**：
      #   · 真源在 addons/eln_ui/app/javascript/vue/eln/（与 Vue3 原型 ELN系统-Vue3 同一份组件）；
      #   · 各 entry 在 config/webpack/webpack.config.js 注册为 eln_*；
      #   · 产物输出到 app/assets/builds/eln_*.js + eln_*.css，视图用
      #     javascript_include_tag 'eln_*' / stylesheet_link_tag 'eln_*' 引用。
      #
      # 🔴 关键：生产 `config.assets.compile=false`，stylesheet_link_tag / javascript_include_tag
      #   走 **Sprockets manifest** 解析。webpack 产物必须被登记进 `assets.precompile`，
      #   才会在 `assets:precompile`（出镜像时）被 fingerprint 进 manifest。
      #   ⚠ 曾误以为「webpack 产物不走 precompile」——实测那样会 AssetNotFound 整页 500
      #     （`The asset "eln_res_center.css" is not present in the asset pipeline`）。
      #   已运行的容器补做手工预编译即可（见 F:/eln开发/patches/*/tools/precompile_entry.rb）。
      #
      # ⚠ 项目列表页的 CSS 自 ADR-0038-D 起**也走宿主 webpack**：真源
      #   addons/eln_ui/app/javascript/vue/eln_project_list/styles/eln_project_list.scss
      #   （AG Grid 主题覆盖，scoped 到 #eln-project-list），产物 app/assets/builds/eln_project_list.css。
      #   旧原型 blob eln_vue3/eln_project_list.css 已退休、不再加载（下方登记随之换成 eln_project_list.css）。
      #
      # 另补登记两个**宿主页面**用的 webpack entry（历史遗留缺口：原先只靠手工预编译进
      # manifest，未登记 ⇒ 一旦重新出镜像就 AssetNotFound 整页 500）：
      #   · eln_project_list.js  —— 项目列表页（/projects）
      #   · vue_teams_table.js   —— 工作区列表页（/users/settings/teams）
      initializer 'scinote_eln_ui.assets' do |app|
        next unless app.config.respond_to?(:assets)

        app.config.assets.precompile += %w[
          eln_project_list.css
          eln_res_center.js eln_res_center.css
          eln_project_detail.js eln_project_detail.css
          eln_exp_detail.js eln_exp_detail.css
          eln_task_detail.js eln_task_detail.css
          eln_apply_detail.js eln_apply_detail.css
          eln_project_list.js
          vue_teams_table.js
        ]
      end
    end
  end
end
