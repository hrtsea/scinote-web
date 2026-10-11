# frozen_string_literal: true

module Scinote
  module ElnUi
    class Engine < ::Rails::Engine
      engine_name 'scinote_eln_ui'
      isolate_namespace Scinote::ElnUi

      # ------------------------------------------------------------------
      # 路由自注册骨架（ticket 01 · .scratch/eln-ui-route-self-registration）
      #
      # 本段只「装能力」，**一条路由都还没搬**——30 条路由此刻仍在宿主
      # config/routes.rb（ticket 02 才迁走）。目的是先把契约与守卫立起来：
      #
      # · ADR-0022 已 Accepted：addon 路由一律由各 engine initializer 自注册，
      #   宿主 config/routes.rb 零 addon 路由；启用/禁用只由 Gemfile 一行决定。
      # · 迁移后若仍是"路由挂宿主"，则注释 Gemfile 行会让宿主路由表指向一个
      #   不再被 Bundler 加载的 controller ⇒ 优雅禁用（宿主照常启动、该 addon 路由 404）
      #   这条保证被打破。这就是本段存在的理由。
      #
      # ⚠️ 为什么必须 `after: :add_routes`：ADR-0022 明确要求显式声明。
      #   Rails 7.2.3.2 下不声明也能工作，但显式声明规避时序坑。
      #
      # ⚠️ 为什么用 `append` 而非 `prepend`：append 保证 addon 路由排在宿主之后，
      #   addon 无法用同名路径覆盖核心路由（ADR-0022 的安全取舍）。代价是 addon 路由
      #   优先级最低 —— 新增路由时必须校验路径不与既有冲突，否则静默 404。
      #
      # 🔴 helper 转发（本段最容易踩的坑，坑 2 已踩过）：
      #   路由搬进 engine 后，`as:` 具名 helper **不会**自动出现在宿主 url_helpers 上。
      #   宿主页面的既有调用点会立刻 NoMethodError。
      #   正解=下面 install_route_helpers!：把转发方法 define 进宿主自己的模块。
      #   **绝不** `include` 引擎那个 url_helpers 模块 —— 它自带 included 钩子
      #   （route_set.rb 的 UrlHelper 模块 included 时 self.dup 再 include 一次），
      #   会自套自直到爆栈，日志里只留一行 "Exiting"，看不出是哪个 addon。
      #
      #   转发而非复制实现：路由形状改了，两边不用各改一遍。
      # ------------------------------------------------------------------
      # 宿主页面上被直接调用的具名路由 helper（迁移后它们只活在 Engine.routes.url_helpers 上，
#   需要在这里留一份转发，否则宿主一渲染就 NoMethodError）。
      #
      # 🔴 清单**从基线读，不手写**。手抄过一次，实测立刻抄错 5 个
      #   （eln_notification_read / eln_project_approver / eln_task_close_action …）
      #   —— 而漏一个/错一个的代价是：只在访问某个页面时才炸，且极难回溯到"路由迁移"。
      #   基线由 test/dump_eln_ui_route_baseline.rb 从真实路由表取样生成。
      BASELINE_PATH = Scinote::ElnUi::Engine.root.join(
        'test', 'fixtures', 'eln_ui_routes_baseline.json'
      ).freeze

      # 只有具名 helper 需要转发；基线里的 ANON 条目（同名路径不同动词，Rails 只命名一次）
      # 没有 helper 可转发，跳过。
      def self.host_route_helpers
        @host_route_helpers ||= begin
          require 'json'
          data = JSON.parse(File.read(BASELINE_PATH))
          data.fetch('routes').filter_map do |r|
            key = r['key']
            key.start_with?('ANON:') ? nil : key.to_sym
          end.uniq.freeze
        rescue StandardError => e
          # 基线读不到时**大声失败**，不要静默变成"不转发"——静默会让迁移后的
          # 宿主页面在运行期才炸 NoMethodError，而那时已经很难定位到基线。
          raise "ELN UI 路由基线读取失败（#{BASELINE_PATH}）：#{e.class}: #{e.message}"
        end
      end

      HOST_ROUTE_HELPERS = host_route_helpers

      initializer 'scinote_eln_ui.routes', after: :add_routes do |app|
        app.routes.append do
          mount Scinote::ElnUi::Engine => '/'
        end

        Scinote::ElnUi::Engine.install_route_helpers!(app)
      end

      # 只 define_method 转发一层，**绝不** include 引擎那个 url_helpers 模块（见上「坑 2」）。
      #
      # 转发清单必须由基线生成而非手写：漏一个，只在访问对应页面时才炸 NoMethodError，
      # 而那种错误极难回溯到"路由迁移"这件事上。
      # 基线见 test/fixtures/eln_ui_routes_baseline.json，守卫见 test/eln_ui_route_baseline_test.rb。
      #
      # ⚠ 清单必须在 module_eval **块外**取出再传参：`module_eval` 里的常量查找走词法作用域，
      #   看不见 `class Engine` 上定义的 HOST_ROUTE_HELPERS。
      #
      # 🔴🔴 **只在该helper 真的存在于引擎侧时才转发**（`engine_helpers.respond_to?` 守卫）。
      #   为什么必须这样：迁移分两步走（ticket 01 只装骨架、路由仍挂宿主；ticket 02 才搬）。
      #   在第 01 步里引擎侧没有任何路由，此时若强行转发：
      #     · 转发体调用 engine_helpers.public_send(...) ⇒ 一旦被调用就 NoMethodError；
      #     · 更隐蔽的是**宿主会用自己的同名 helper 覆盖掉这个转发**（宿主路由表已经
      #       有这些名字，生成的定义在后、优先级更高），于是转发静默失效——
      #       实测 helper 的 owner 仍是宿主的 ::ROUTES，看起来"装好了"其实没生效。
      #   守卫让 01 阶段明确跳过（此时宿主原生 helper 就是权威，不需要转发），
      #   02 迁完路由后引擎侧 helper 就位，转发生效。幂等、可重复执行。
      def self.install_route_helpers!(app)
        engine_helpers = Scinote::ElnUi::Engine.routes.url_helpers
        helper_names = HOST_ROUTE_HELPERS

        forwarded = []
        skipped  = []

        app.routes.url_helpers.module_eval do
          helper_names.each do |helper_name|
            unless engine_helpers.respond_to?(helper_name)
              skipped << helper_name
              next
            end

            define_method(helper_name) do |*args, **kwargs, &block|
              engine_helpers.public_send(helper_name, *args, **kwargs, &block)
            end
            forwarded << helper_name
          end
        end

        # 只在有实际动作时打日志，避免每次启动刷屏；启动期日志噪音会掩盖真异常。
        if forwarded.any?
          Rails.logger&.info(
            "[eln_ui] 路由 helper 转发已安装：#{forwarded.size} 个" \
            "#{skipped.any? ? "（跳过 #{skipped.size} 个引擎侧尚未定义）" : ''}"
          )
        end

        { forwarded: forwarded, skipped: skipped }
      end

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
