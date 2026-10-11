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

      # 🔴 addon 迁移路径注册（2026-10-11 补，此前**从未注册过**）。
      #
      # 症状：`rails db:migrate:status` 里每一条 eln_ui 迁移都显示
      #   `up  2026xxxx  ********** NO FILE **********`
      #   —— 版本在 schema_migrations 里，但 Rails 找不到对应文件（NO FILE）。
      # 原因：engine 没有 append_migrations，db/migrate 没进 `app.config.paths['db/migrate']`，
      #   rails 只认得**文件**，不认得**版本号**。
      # 影响：新环境/新库上 `rails db:migrate` 根本不会执行 eln_ui 的迁移 ⇒
      #   eln_ui_* 全系列表缺失（项目档案、任务关闭申请、消耗核销……）。
      #   本项目一直靠 sync_migrations.sh 手工 push 绕过，属既有债。
      #
      # 为什么现在补：新增的 20261011120000/130000 两条要上线，靠手工脚本意味着
      #   「换机器/换人就漏跑」。补注册后跟其他 addon 行为一致。
      #
      # ⚠ 补注册**不会**重跑历史迁移：版本已在 schema_migrations 里，
      #   migrate 只认 up/down 状态。NO FILE 的历史条目会一直显示 NO FILE
      #   （Rails 对已up 但文件缺失的迁移就是这个提示），属正常、不阻断。
      initializer :eln_ui_append_migrations do |app|
        unless app.root.to_s.match?(root.to_s)
          config.paths['db/migrate'].expanded.each do |expanded_path|
            app.config.paths['db/migrate'] << expanded_path
          end
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
      #   已运行的容器补做手工预编译即可（见 F:/elndev/patches/*/tools/precompile_entry.rb）。
      #
      # ⚠ 项目列表页的 CSS 自 ADR-0038-D 起**也走宿主 webpack**：真源
      #   addons/eln_ui/app/javascript/vue/eln_project_list/styles/eln_project_list.scss
      #   （AG Grid 主题覆盖，scoped 到 #eln-project-list），产物 app/assets/builds/eln_project_list.css。
      #   旧原型 blob eln_vue3/eln_project_list.css 已退休、不再加载（下方登记随之换成 eln_project_list.css）。
      #
      # 另补登记**宿主页面**用的 webpack entry（历史遗留缺口：原先只靠手工预编译进
      # manifest，未登记 ⇒ 一旦重新出镜像就 AssetNotFound 整页 500）：
      #   · eln_project_list.js  —— 项目列表页（/projects）
      # （vue_teams_table.js 工作区列表页的 precompile 登记已迁回宿主
      #  config/initializers/assets.rb，与 vue_team_new 等宿主 team 页一致。）
      #
      # ⚠ 2026-10-11 补两个新面孔（Vue3 重建引入，此前都漏登记，manifest 实测命中数为 0）：
      #   · eln_vue3/eln_project_list.js + .css —— **V2 生产页 index.html.erb 引用它们**
      #     （第 19 行 asset_path 引 CSS、第 31 行 javascript_include_tag 引 JS；不再引 webpack 的
      #     eln_project_list）。它们是 eln_vue3/ 目录下的手写 blob，Sprockets 只在**显式登记**
      #     后才进 manifest；addon 的 app/assets/{javascripts,stylesheets} 并不会被自动全量索引。
      #     未登记 ⇒ 生产 assets.compile=false 下 AssetNotFound ⇒ 整页 500（ADR-0038 记过同类坑）。
      #     🔴 **JS 与 CSS 必须成对登记**：只补 .js 漏 .css 时页面照样整页 500
      #       （asset_path 解析失败直接抛 AssetNotFound，实测 2026-10-11 首次浏览器验收就撞上）。
      #       补登记后逐个 grep manifest 复核，别只看 JS 那一个。
      #   · project_list_v1.js / .css —— 孤儿 V1 测试页（/eln_project_list_v1）
      #     用的 webpack entry。与 V2 并排做比对，不接生产主路由，但只要路由可达
      #     就得能出资产，否则那条路由 500。
      #
      # 🔴 2026-10-11 补 eln_project_list_v3.{js,css}（生产列表页新真源）：
      #   项目列表页此前加载的是 `eln_vue3/eln_project_list.js` —— 一份 152KB / 5 行
      #   压缩**手写 blob**，未纳入 git、全仓找不到任何构建脚本。后果：vue/ 下的
      #   组件改动（DateField 等）即使正确编译进 webpack 也到不了生产页
      #   （浏览器实测生产产物里 vue-datepicker 标记 dp__menu 为 0）。
      #   视图已改引`eln_project_list_v3`，这里配套登记。
      #   ⚠ 下面两行 `eln_vue3/*` **暂留**：视图已不再引用，但删登记前先确认没有
      #   其他视图/邮件模板还在引 —— 漏引AssetNotFound 是整页 500 级别的事故。
      #   确认无人引用后与blob 文件一并清理（届时本注释可删）。
      # ⚠ .js 与 .css **必须成对登记**，只补一个照样整页 500（AssetNotFound）。
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
          eln_project_list_v3.js eln_project_list_v3.css
          eln_vue3/eln_project_list.js
          eln_vue3/eln_project_list.css
          project_list_v1.js project_list_v1.css
        ]
      end
    end
  end
end
