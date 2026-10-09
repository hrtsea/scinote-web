# ADR-0034：工作区列表 Vue 化（Vue3 + AG Grid，源码归 eln_ui，构建走宿主 webpack）

- 状态：**Accepted**（2026-10-07，用户拍板）→ **局部修订**（见文末「修订 rev 2026-10-08」：由 AG Grid 改为「复刻原生」）
- 决策人：用户
- 相关：ADR-0031（原生库存列表 Vue3 + AG Grid）
- 取代：本文早先版本的「预打包单体 `.js` + Sprockets（对齐 addon blob）」方向——该版本曾落地过，后经实测比对被否决并改用本方案。
- 影响面
  - `addons/eln_ui/app/javascript/packs/vue_teams_table.js`（新增，webpack entry）
  - `addons/eln_ui/app/javascript/vue/teams/table.vue`（新增，AG Grid SFC）
  - `config/webpack/webpack.config.js`（注册 entry）
  - `app/views/users/settings/teams/index.html.erb`（改挂 `#teams-table-vue` + props）
  - `app/controllers/users/settings/teams_controller.rb`（注入 `@teams_payload`）

## 背景

「设置 → 工作区」列表原本是 **Rails ERB + jQuery DataTables**：`TeamsDatatable` 服务端分页，
前端 `datatable.js` 用 `$('#teams-table').DataTable({ serverSide: true })`。

用户要求把它 Vue 化，对齐 ADR-0031 已确立的「原生库存列表 = Vue3 + AG Grid」体验，并进一步要求
**把这份 Vue 化放进 eln_ui addon**。

## 决策

**源码放在 eln_ui addon，构建挂在宿主 webpack。** 即 eln_ui 拥有 Vue 源码，但不自带构建管线，
与 `addons/project_insights` 一样把源码交给宿主 `config/webpack/webpack.config.js` 注册 entry。

1. **源码位置**（可审阅、可 diff、可 review，这是本方案的核心收益）
   - entry：`addons/eln_ui/app/javascript/packs/vue_teams_table.js`
   - 组件 SFC：`addons/eln_ui/app/javascript/vue/teams/table.vue`
2. **注册方式**：在 `webpack.config.js` 的 `entryList` 手动追加一条
   `vue_teams_table: './addons/eln_ui/app/javascript/packs/vue_teams_table.js'`。
   （addon 自动扫描只认顶层 `packs/*.js`，手动登记最稳。）
3. **数据契约**：仍随页面 SSR 注入，由 controller 的 `teams_payload` 产出，经 ERB 绑成组件 props
   （`:teams` / `:can-create` / `:new-team-url`）。**不新增 JSON 端点**。
4. **交互**：AG Grid 客户端排序 + 分页（10/页）+ `quickFilter` 搜索；名称列渲染成 `<a href=show_url>`；
   「操作」列按 `can_leave` 渲染「退出」按钮，走 `fetch DELETE → destroy_user_team_path(ua, leave: true)`。
5. **Turbolinks**：entry 内联 `mountWithTurbolinks`（照抄 `app/javascript/packs/vue/helpers/turbolinks.js`），
   避免 addon 跨目录相对路径的脆弱引用。
6. 旧 `TeamsDatatable` / `datatable.js` / `index.js` / `#datatable` action+route / `.teams-datatable` SCSS
   已在切换到本方案前清理掉。

## 为什么不用「addon 预打包 blob」（eln_ui / workbench 的老路）

初版走的就是这条路（esbuild 打单体 IIFE → 提交 minified `.js` → Sprockets）。实测比对后否决：

| 维度 | 宿主 webpack 源码（采纳） | addon 预打包 blob（否决） |
| --- | --- | --- |
| 源码在仓可读/diff | ✅ `.vue` 源码可 review | ❌ 提交 minified 二进制，改一行要整体重打 |
| 组件复用 | ✅ 未来可直接吃 `app/javascript/vue/shared/**` | ❌ 各 addon 各造一遍 grid |
| 版本升级 | 改 `package.json` 一处 | 每个 addon 重新外部构建 |
| 依赖管理 | 受 `package.json` / `yarn.lock` 约束 | 游离在外，版本靠人工记忆 |
| 部署 | 需走 `yarn build`（宿主已有此管线） | 只需 cp + Sprockets |

**更正一条先前误判**：曾以为「宿主 webpack 只有一个共享 Vue 运行时，blob 会凭空多一份」。
实测 `webpack.config.js:247` 是 `LimitChunkCountPlugin({ maxChunks: 1 })`——
**宿主每个 entry 本就是自包含单文件（各带一份 Vue）**。两者在运行时冗余上**平手**，
真正的分水岭只有「源码可审阅」与「依赖受管」两条，且都指向本方案。

## 关键事实（实测，勿凭印象改）

- **宿主 webpack 出口是 `app/assets/builds/`**，再由 Sprockets 预编译进 `public/assets`（容器里可见
  `vue_repositories_table-<digest>.js`）。视图用 **`javascript_include_tag 'vue_teams_table'`**（Sprockets 帮手，
  不是 `javascript_pack_tag`，后者在本仓未被使用）。
- **宿主 webpack 本来就吃 addon 源码**：`webpack.config.js` 已注册
  `addons/project_insights/app/javascript/packs/insights_charts.js`。所以 blob 不是被迫，是历史选择。
- **Vue 引入写法必须与宿主一致**：76 个宿主 pack 全部是
  `import { createApp } from 'vue/dist/vue.esm-bundler.js'`（全量含编译器版，因为要把挂载点 innerHTML 当模板编译）。
  配套的 `__VUE_OPTIONS_API__: true` 已由 `webpack.config.js:252` 的 DefinePlugin 注入，**不需要自己再加**。
- AG Grid v32 靠 `import { AgGridVue } from 'ag-grid-vue3'` 即自动注册 community 模块，宿主 `shared/datatable/table.vue`
  就是这么用的；主题 CSS 由 `application.scss` 全局加载，**组件无需再引 ag-grid CSS**。
- **生产运行时容器不是构建环境**（重要）：镜像把 devDeps 剪了，`@babel/plugin-*` 系列缺失，且 `npm`/`yarn` 均不可用。
  `bin/yarn` 只是个 Ruby shim（在 PATH 里找不到真 yarn 就报错）；真 yarn 藏在 corepack 里：
  `node /usr/share/nodejs/corepack/dist/yarn.js`。**真实 build 应在镜像构建期做**，不要在运行时容器里追求可重复构建。
- **`babel.config.js` 存在 latent bug**：它 require 的 5 个包里，只有 `@babel/plugin-proposal-private-property-in-object`
  在 `package.json` 里声明过，其余 4 个（`plugin-syntax-dynamic-import`、`plugin-proposal-private-methods`、
  `plugin-proposal-class-properties`、`plugin-proposal-object-rest-spread`、`babel-plugin-transform-react-remove-prop-types`）
  **从未声明**。镜像里靠缓存/传递依赖侥幸存在，一旦 devDeps 被剪就全线崩（表现为 76 个连锁 `Cannot find module`）。
  → **待办：把这 5 个补进 `package.json` 并重生 `yarn.lock`**，否则任何干净环境都无法 `yarn build`。
- 路由 helper 是 **`destroy_user_team_path(id, leave: true)`**（route `as: 'destroy_user_team'`），不是 `user_teams_path`。
- **`UserRole.owner_role` 返回的是一个 `id` 为空的未持久化 `UserRole`（宿主 Bug）**。拿它去做
  `where(user_role: owner_role)` 会退化成 `user_role_id IS NULL` 而恒查不到行。**禁止在查询里使用它**，
  要判 owner 请用已加载记录上的 `user_role.owner?`。
- **「能否退出」只能走后端同一口径**：`UserTeamsController#destroy` 用的是
  `@user_assignment.last_with_permission?(TeamPermissions::USERS_MANAGE)`（最后一个持**团队管理权限**的人不可退出，
  含自定义角色）。前端必须调用同一个方法，禁止自己按 Owner 名字判断，否则两边口径分叉。
- **Vue in-DOM 模板里写不了 `window`**：Vue 3 会把模板表达式编译成 `_ctx.xxx`，而 globals 白名单只有
  Math/JSON/Date/console 等，`window` 不在其中。SSR 全局必须先落到**根组件的 `data`** 上，模板再绑 `:teams="teams"`。
- **不要在运行时容器里跑全量 webpack**：一次性重编全部 ~110 个 entry 会把 Docker Desktop 拖到 API 全 500、
  整机站点不可达。要就地验证就用一个临时配置 `require('./webpack.config.js')` 后覆写 `entry` 只编目标 entry
  （本次 1.1MB / 数十秒完成，全量则需十几分钟且有崩溃记录）。
- 缺失的 babel 插件可用 **tarball 直装**绕开 `yarn add`：`curl` 拉
  `https://registry.yarnpkg.com/<pkg>/-/<pkg>-<ver>.tgz` 解压到 `node_modules/<pkg>` 即可，
  避免全树重解时撞上 `tui-image-editor` 的 git 依赖与 postinstall。注意补传递依赖
  （本次还缺 `@babel/plugin-syntax-object-rest-spread`）。
- 生产 `Rails.application.assets` 为 **nil**（`assets.compile=false`），脚本里要手工
    `Sprockets::Environment.new` + 追加 `Rails.application.config.assets.paths` 再 `Manifest#compile`。
- **部署顺序是安全的**：`Dockerfile.production` 的 builder 阶段先
  `yarn install → yarn build → build:css → tailwindcss:build`，之后才 `rails assets:precompile`，
  runner 阶段整体 COPY。所以新增 entry 在下次出镜像时必然被打包进 `app/assets/builds` 并被预编译。
- （已废弃的早期判定，保留仅备查）：一度用 `where(user_role: owner_role).where.not(id: ua.id)` 判断
  「是否最后一个管理员」，既踩了 `owner_role` 空 id 的坑，口径也与后端 `TeamPermissions::USERS_MANAGE` 不一致。
  现统一改为调用 `ua.last_with_permission?(TeamPermissions::USERS_MANAGE)`。

## 验证策略

1. 容器内 `webpack --config ./config/webpack/webpack.config.js` 成功，`app/assets/builds/vue_teams_table.js` 产出。
2. Sprockets 编译后 `public/assets` 出现 `vue_teams_table-<digest>.js`，HTTP GET 该 asset 返回 200 且内容含 Vue/AG Grid 标记。
3. Rails 真会话集成检查（`verify_teams_vue.rb`，Warden test mode）：
   `GET /users/settings/teams` → 200，含 `#teams-table-vue` 挂载点 + `vue_teams_table` 脚本引用 + payload 注入；
   **逆向护栏**：旧的 `#teams-table` / `teams-datatable` / 宿主 blob 引用必须消失。
4. 权限分叉自证：system_admin 看全队；普通 member 只看自己所属。
5. **退出按钮护栏必须自证真值可达**：同一份数据里既要有 `can_leave=true` 的行（同队存在第二个持
   `TeamPermissions::USERS_MANAGE` 者），也要有 `can_leave=false` 的行（自己是最后一个）。
   只出现单一取值说明判定退化成了常量——那比没有护栏更危险。

## 后果（Consequences）

**获得**

- Vue 源码进仓，可 code review、可 diff，不再是黑盒 blob；同时满足「归到 eln_ui」的归属要求。
- 依赖受 `package.json` 约束，Vue / AG Grid 升级是改一处版本号而非逐个 addon 重打。
- 与库存列表同管线同组件栈，未来可直接复用 `shared/**`。

**失去 / 代价**

- 部署必须走 `yarn build`（宿主 webpack 全量构建），不再是「cp 一个文件 + Sprockets 单文件 compile」那么轻。
- `addons/eln_ui` 从此依赖宿主构建管线，addon 的独立性下降（这也是 `project_insights` 已经接受的取舍）。
- 运行时容器无法就地重建本 entry，任何调试都需要在具备完整 devDeps 的环境里跑 webpack。

---

## 修订 rev 2026-10-08：由「AG Grid」改为「复刻原生」

- 状态：**Accepted**（2026-10-08，用户拍板）
- 触发：用户指出 `/users/settings/teams` 的**功能与 UI 与原生页面不一致**，要求「根据原生的页面走 vue 化路子，重新 vue 化」。
- 用户三项明确决策：① 复刻程度＝**完全复刻原生**；② 数据链路＝**恢复服务端分页排序**；③ 最终形态＝**Vue 复刻原生 + 服务端分页排序**。

### 改了什么

| 维度 | 修订前（AG Grid） | 修订后（复刻原生） |
| --- | --- | --- |
| 表格 | AG Grid（`.ag-theme-alpine`） | 原生 Bootstrap `.table.dataTable` + 4 列（名称/角色/成员/退出） |
| 列 | 7 列 | **4 列**（名称/角色/成员/退出；退出列无表头，与原生 thead 一致） |
| 搜索 | AG Grid `quickFilter` 搜索框 | **无搜索框**（对齐原生 `dom: 'RBltpi'`，不含 `f`） |
| 新建入口 | 表内工具条按钮 | **回到页头** `#new-team-button`（`sn-icon-new-task`，system_admin 可见） |
| 名称列 | 一律可点 `show_url` | **仅「可管理该工作区」时可点**（原生为 `owner?`；此处以宿主 `can_manage_team?` 为准，避免渲染出点进去 403 的链接） |
| 退出 | `window.confirm` + `fetch DELETE` | **原生弹窗** `#modal-leave-user-team`（服务端渲染 + AJAX 填充 + `modal('show')`；成功后 `location.reload()`） |
| 分页/排序 | AG Grid 客户端 | **服务端**（JSON 端点，语义对齐原生 `TeamsDatatable`：Sortable name/role/members） |
| 文案 | 组件内硬编码/`window.I18n` | **服务端 ERB `t(...)` 注入 `labels` prop**（见下「铁律」） |

### 数据链路：新增精简 JSON 端点

- `POST users/settings/teams/datatable`（`as: teams_datatable`），契约 `{page, per_page, sort, dir}` → `{rows, total}`。
- 渲染权收归 Vue，但**分页/排序语义与原生 `TeamsDatatable` 一致**；判定（`can_manage` / `can_leave` / 记录范围）全部集中在 controller 私有方法，单一真源。
- 保留 `system_admin` 全量可见：`workspace_scope = current_user.system_admin? ? Team.all : @user.teams`。
- `can_leave` 仍严格对齐后端 `UserTeamsController#destroy` 的 `assignment.last_with_permission?(TeamPermissions::USERS_MANAGE)`，不按 Owner 名字自判。

### DOM 复用 DataTables 类名

组件刻意沿用 `.dataTables_wrapper / .dataTables_length / .dataTables_info / .dataTables_paginate ul.pagination`，
以直接复用宿主既有的 `app/assets/builds/datatables.css`（须 `stylesheet_link_tag 'datatables'`）与 Bootstrap 样式，
观感与原生一致。分页页码算法与宿主 `app/javascript/vue/shared/datatable/pagination.vue` 同款（最多 5 个页码）。

### 验证（真浏览器，生产容器）

`F:/eln开发/_prod_shots/_verify_teams_page.js` —— **20/20 PASS**：thead = `["Workspace","Role","Members",""]`、
`.ag-theme-alpine` 消失、无搜索框、`#new-team-button` 存在、`infoText` 已解析（无 missing 翻译）、
点表头触发新请求、退出弹窗可见且含表单、`datatable` 端点全 200、0 console error / 0 pageerror。

### 两条新铁律（本轮踩坑得出，通用）

1. **webpack 产物必须登记进 `config.assets.precompile`**（生产 `assets.compile=false`）。否则
   `javascript_include_tag` 走 Sprockets manifest 解析失败 → `AssetNotFound` → **整页 500**。
   已补登记历史缺口（`eln_ui` engine 的 `precompile` 列表）。
2. **客户端 i18n 在本检出不可靠** ⇒ 文案一律由服务端 ERB `t(...)` 注入为 prop。
   根因链：`app/assets/javascripts/i18n/translations.js` 是**已提交的生成产物**（按字母序 JSON），
   而 `config/i18n-js.yml` 缺失（`rake i18n:js:export` 静默 no-op），且 `i18n_bundle.js` 依赖的
   `scinote/i18n/application` 已随 i18n addon 被摘除 ⇒ **新增 key 无法进入客户端 bundle**，
   且 `i18n_bundle.js` 在本检出**根本无法重新预编译**。服务端注入是唯一可靠且单一真源的方案。

---

## 修订 rev2 2026-10-08（同日晚）：恢复「ID / 创建人 / 创建时间」列

- 状态：**Accepted**（2026-10-08，用户指出后拍板）
- 触发：用户指出「以前要求过在列表里增加**创建人、创建时间**等内容」——该需求 2026-10-07 已在原生
  DataTables 版落地（`TeamsDatatable` 7 列，真会话 23/23 PASS），但 10-08 的「复刻原生」重写按
  原生 `fbe24fd3d^` 的 4 列口径把它**一并回退掉了**。本修订恢复之。
- **教训**：「复刻原生」的基准是原生**外观与交互**，不覆盖用户的显式增量需求；列集=用户需求 ∪ 原生列，
  以用户需求优先。

### 决策

- 列 = **7 列**：名称 / ID / 创建人 / 创建时间 / 角色 / 成员 / 退出（列顺序沿用 10-07 版）。
- 其余一切（无搜索框、页头新建按钮、名称仅可管理时可点、原生弹窗退出、最后管理员禁用、
  服务端 JSON 分页排序、文案服务端注入）不变。
- 创建人真源 = `team.created_by&.full_name`（`users.full_name` 列；`Team belongs_to :created_by, optional: true`），
  空值回退 `na` 文案；创建时间服务端格式化 `%Y-%m-%d %H:%M`（避免客户端时区/格式分叉）。
- 排序新增 `id` / `created_by`（代码侧 sort_by，对齐 10-07 口径）/ `created_at`，仍 Ruby 侧排序后分页。
- locale 复用既有 `users.settings.teams.index.thead_id / thead_created_by / thead_created_at`
  （10-07 添加，两语言均在，无需新增 key）。

### 验证（真浏览器，生产容器，2026-10-08）

`_prod_shots/_verify_teams_page.js` —— **23/23 PASS**：thead = `["Workspace","ID","Created by","Created at","Role","Members",""]`、
首行创建人=Admin、创建时间=`2026-10-07 05:04`（与 10-07 首次落地值同源对拍一致）、
点「创建人」表头触发排序请求 200、其余（无搜索框/弹窗/退出禁用态/0 error）全部保持。
产物 digest `vue_teams_table-78de8a30…js`（252,386B）。

---

## 修订 rev3 2026-10-08（晚）：换用 AG Grid（参照 /projects shared/datatable 栈）

- 状态：**Accepted**（2026-10-08，用户拍板：「参照 /projects 页面 换用 ag-grid 重新实现，
  列宽可以调整，把分页放到表格下方」）。本修订取代 rev/rev2 的「复刻原生 Bootstrap 表格」形态；
  rev2 的**列集（7 列）不变**，仅交付形态变更。
- 落地：复用宿主原生 AG Grid 栈 `app/javascript/vue/shared/datatable/table.vue`
  （ADR-0035 V2.0 拍板、/projects 同款），addon 侧只写薄封装
  `addons/eln_ui/app/javascript/vue/teams/table.vue` + 两个 cellRenderer
  （name_renderer / leave_renderer，以**直接组件引用**挂 columnDefs，同 /projects 的
  FavoriteRenderer 用法）。
- 关键配置：`scrollMode='pages'`（表格下方分页条：Show N rows + 条目计数 + 页码）、
  `defaultColDef.resizable`（列宽可调，栈自带）、`loadMethod='post'`、`withCheckboxes=false`、
  `toolbarActions={}`（无搜索框，与原生一致）、`skipSaveTableState=true`
  （关闭 user_settings 列状态持久化——栈的自愈分支按「columnDefs.length+1（选择列）」校验，
  无勾选列场景不适用；且规避 ADR-0035 V2.1 记录的「自愈写丢列」bug 类）。
  名称列由栈自动钉左（field==='name' 特判，与 /projects 一致）。
- 后端契约变更：`POST users/settings/teams/datatable` 由 `{page,per_page,sort,dir}→{rows,total}`
  改为 shared/datatable 原生协议 `{page,per_page,order:{column,dir},search,view_mode,filters}
  → JSON:API {data:[{id,type,attributes}], meta:{total_pages,total_count,filtered_count}}`；
  排序 colId=field（name/id/created_by/created_at/role/members_count）；
  per_page 选项对齐栈下拉 `[10,20,50,100]`（默认 20）。
- 🔴 新坑（pack 挂载）：根组件**必须** `createApp({})` + `app.component('TeamTable', …)` 全局注册，
  让挂载点 innerHTML 作为 **in-DOM 模板**解析——ERB 注入的 `:data-source`/`labels` props 才会被绑定。
  若 `createApp(TeamsTable)` 直接挂根（SFC 自带模板），in-DOM 属性被整体忽略 ⇒
  `dataUrl=undefined` ⇒ 实测 `POST /users/settings/undefined` 404（2026-10-08 实机排查）。
- 验证（生产容器 + 真浏览器 playwright，2026-10-08）：`_prod_shots/_verify_teams_page.js`
  **21/21 PASS** —— `.ag-theme-alpine` 挂载 / 7 列文案（CustomHeader `.customHeaderLabel`）/
  无勾选列 / 每列 resize 手柄 / 行 `e2e-TB-row-40|1` / 名称列钉左且 can_manage 可点 /
  退出按钮 enabled+disabled=行数（最后管理者禁用保持）/ 分页条 `e2e-CO-tableInfo` 含
  Show 下拉+条目文案 / 点 `e2e-CO-tableHeader-created_by` 触发服务端排序 200 /
  退出弹窗（原生 modal）正常 / datatable 全 200 / 0 console error / 0 pageerror。
  产物 digest `vue_teams_table-d0762f71…js`（1,712,556B，含 AG Grid + js-routes）。
