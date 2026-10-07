# ADR-0034：工作区列表 Vue 化（对齐 ADR-0031 的 Vue3 + AG Grid 原生列表范式）

- 状态：**Accepted**（2026-10-07，用户拍板：① 组件走「自建轻量 AG Grid」；② 打包范式对齐 eln_ui / workbench addon 的「预打包单体 .js + Sprockets」路线）
- 决策人：用户
- 相关：ADR-0031（原生列表 Vue3 + AG Grid）、DEC-012（自研能力挂载原生视图不新造外壳）
- 影响面：`app/views/users/settings/teams/index.html.erb`、`app/assets/javascripts/users/settings/teams/teams_table.js`(新增，预打包)、`users/settings/teams` 控制器（注入 `window.__ELN_TEAMS__`）

## 背景

「设置 → 工作区」列表当前是 **Rails ERB + jQuery DataTables**（`teams_datatable.rb` 服务端分页，数据走 `teams_datatable_path(format: :json)`，前端 `datatable.js` 用 `$('#teams-table').DataTable(...)`）。

ELN 的「Vue 化」既定范式由 ADR-0031 确立：原生库存列表已是 **Vue3 + AG Grid**，挂载机制是  
`createApp().component('RepositoriesTable', ...).mount('#repositoriesTable')`，经 `mountWithTurbolinks`  
挂到 DOM id，数据经 `shared/datatable/table.vue`（AG Grid）向 `dataUrl` 拉取，契约是  
`{ data: [...行...], meta: { total_count } }`（JSON:API 信封，`per_page`/`search`/`order` 作 GET 参数）。

用户要求工作区列表同样 Vue 化，并明确「对齐库存列表的 Vue3 + AG Grid 方案」。

## 决策（采纳方案 B：自建轻量 AG Grid 组件 ＋ 对齐 addon 预打包范式）

工作区列表不重画、不复用仓库形 DataTable，而是**自建一个最小 AG Grid 组件**，并**严格对齐 eln_ui / workbench addon 的 Vue 交付范式**（已普查确认：本仓 addon 的 Vue 全是「外部构建 → 提交单体 `.js` → Sprockets 提供 → 挂 DOM id → 数据走 `window.__ELN_*` 全局」）。

1. `index.html.erb` 把 `<table id="teams-table">…</table>` + `datatable.js` 替换为  
   `<div id="teams-table-vue"></div>` ＋  
   `<%= javascript_include_tag 'users/settings/teams/teams_table', nonce: content_security_policy_nonce %>`。  
   控制器在视图里注入 `window.__ELN_TEAMS__ = { teams: [...], canCreate, newTeamUrl, leaveUrlTpl }`。
2. 新增**预打包单体** `app/assets/javascripts/users/settings/teams/teams_table.js`：  
   外部用 esbuild 把 `vue@3.5.16` + `ag-grid-community@32.3.9` + `ag-grid-vue3@32.3.9` 打成一个 IIFE，  
   内部 `createApp({...}).mount('#teams-table-vue')`，读 `window.__ELN_TEAMS__` 渲染 7 列 AG Grid  
   （名称/ID/创建人/创建时间/角色/成员数/操作），客户端排序+分页+quickFilter 搜索，  
   「新建工作区」按钮按 `canCreate` 渲染，行的「退出」按钮 DELETE `leaveUserTeamPath(id)?leave=1`。
3. **不新增 JSON 端点**：数据随页面 SSR 注入 `window.__ELN_TEAMS__`，与 eln_ui 完全一致（避免再开一个 API 面）。
4. 旧 `teams_datatable.rb` / `datatable.js` 在实现并验证通过后删除（先保留做回滚锚点）。
5. **部署**走已验证的 Sprockets 单文件 compile 配方（容器内 `docker exec -u root ... manifest.compile('users/settings/teams/teams_table.js')` + restart），**不碰宿主 webpack graph**，比库存列表的 `yarn build` 全量构建轻得多。

## 被否决的方案继续执行

> 方案
>
> 否掉理由

> A. 复用宿主 `shared/datatable/table.vue`（仓库形 DataTable）
>
> 该组件按仓库语义塑形（archive/cards/filters/列管理），需逐项用 prop 关掉，隐性耦合高；且工作区列表是轻量场景，不值。

> 宿主 webpack packs（仿 `vue_repositories_table` entry）
>
> 每改一次要 `yarn build` 全量重编宿主 webpack graph，慢且波及所有 pack digest；与 addon 既成范式（预打包单体 .js）不一致。

> 保留 jQuery DataTable 不迁
>
> 与「Vue 化」诉求直接矛盾。

> 在 Vue 里包一层 jQuery DataTable
>
> 反模式。

## 关键事实（实测，勿凭印象改）

- **本仓 addon 的 Vue 交付范式（eln_ui / workbench 一致，已普查）**：每个 Vue 功能 = 一个**预打包单体 `.js`**（含 Vue 运行时+应用+组件，minified），提交到 `app/assets/javascripts/<addon>/eln_vue3/<feature>.js`；视图用 `javascript_include_tag '<path>.js', nonce: content_security_policy_nonce` 引入；数据走 `window.__ELN_*` 全局（ERB 在视图赋值），bundle 内 `createApp(...).mount('#mount-id')`。仓内**无 `.vue` 源、无 build 配置**——都是外部构建后提交的产物。
- `index.html.erb` 现有的 `<table id="teams-table">` + `datatable.js` 是 jQuery DataTables，将被替换；`datatable.js` 走 Sprockets，故新 bundle 也走 Sprockets（同源，可复用已验证的单文件 compile 配方）。
- 全局 AG Grid 主题 CSS 已由 `app/javascript/packs/application.scss` 经 `application_pack_styles` 在 layout 全局加载，**bundle 只需打包 JS**（无需再引 ag-grid CSS）。
- 版本须对齐宿主：`vue ^3.5.16`、`ag-grid-community ^32.3.9`、`ag-grid-vue3 ^32.3.9`。
- 数据规模小（个人所属团队数 + system_admin 看全部，至多几十），故**客户端排序/分页/搜索**即可，无需服务端分页端点。
- 退出端点：`DELETE /users/settings/user_teams/:id`（`user_teams#destroy`），带 `params[:leave]=true` 即「退出」（非销毁），成功后跳 `teams_path`。

## 后果（Consequences）

**获得**

- 与 eln_ui / workbench 等现役 addon **同一套 Vue 交付范式**，团队认知统一，部署轻（Sprockets 单文件 compile，不碰宿主 webpack graph）。
- 自建轻量 AG Grid 组件，无仓库形 DataTable 的隐性耦合；7 列 + 排序 + 分页 + 搜索 + 退出/新建 全部自包含。
- 数据 SSR 注入 `window.__ELN_TEAMS__`，不新增 API 面，与 eln_ui 一致。

**失去 / 代价**

- 需要一个**外部构建步骤**产出单体 `.js`（本仓 addon 惯例如此；用 esbuild 本地打包后提交）。bundle 是黑盒产物，调试不如在仓源码直观。
- 引入对 Vue 3.5 / AG Grid 32 版本的构建期依赖：升级宿主 Vue/AG Grid 时需同步重打此 bundle。
- Turbolinks 生命周期、Vue 内「退出 / 新建」动作需重新接线并验证（沿用 eln_ui 的 mount 套路 + 全局 CSRFF token）。

## 验证策略

1. 本地 esbuild 打包 `teams_table.js` 成功（IIFE，含 Vue+AG Grid），md5 记录。
2. `docker cp` 进容器 `app/assets/javascripts/users/settings/teams/`，`docker exec -u root` 跑 Sprockets `manifest.compile('users/settings/teams/teams_table.js')`，确认 manifest 出现新 digest；`docker restart`。
3. Rails 集成测试（沿用 `verify_teams_columns.rb` 套路）：`GET /users/settings/teams` → 200 含 `#teams-table-vue` 挂载点 + `teams_table` 脚本引用；真会话 UI 验证 7 列渲染、排序、搜索、退出按钮、system_admin 看全队。
4. **逆向护栏**：确认旧的 `#teams-table` 与 `datatable.js` teams 引用已清除，避免两张表并存。
5. 全绿后删除 `teams_datatable.rb` 与 `datatable.js`，并清理仅 jQuery 表用的孤立 i18n key（若仍被 Vue 复用则保留）。

## 验证策略

1. 容器内 `yarn build` 成功，manifest 出现 `vue_teams_table` → 新 digest。
2. Rails 集成测试（沿用 `verify_teams_columns.rb` 套路）：
   - `GET /users/settings/teams` → 200，含 `#teamsTable` 挂载点 + `vue_teams_table` 脚本引用；
   - `GET /users/settings/teams.json` → 200，`{data:[…7 字段…], meta:{total_count}}`，分页/排序/搜索参数生效。
3. **逆向护栏**：确认旧的 `#teams-table` 与 `datatable.js` teams 引用已清除，避免两张表并存。
4. 真会话 UI 自证：排序、搜索、退出工作区按钮、system_admin 看全队均正常。
