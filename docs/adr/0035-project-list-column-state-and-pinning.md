# ADR-0035: 项目列表列状态持久化与钉列（V1.33 → V1.34 多列钉住）

## Status
Accepted（2026-10-07）

> **V1.34 修订（同日晚）**：原 V1.33 的「单锚点冻结前缀」钉列语义已被 **多列独立钉住**
> 取代（对齐原生 `/projects` 的「可同时钉多列」）。本 ADR 的持久化端点 / 部署管线不变，
> 仅钉列的数据模型（`pinnedUpTo` 单锚点 → `pinned[]` 数组）与渲染机制（前缀 sticky →
> `order` 归拢 + `position:sticky`）变更。旧存档 `pinnedUpTo` 通过 `prefixUpTo` 自动迁移。

> **V2.0 修订（同日晚，落地形态）**：V1.34 描述的是**原型仓 `ELN系统-Vue3` 的手写 flex 网格方案**
> （`pinned[]` 数组 + `order`/`position:sticky` 复刻）。经用户拍板「选项 B（保 ELN 功能，更稳）」，
> **线上真源改为引用原生 AG Grid 栈** `app/javascript/vue/shared/datatable`（薄封装 AG Grid v32.3.9），
> 而非复制/重写原型。多列钉住 / 列重排 / 显隐 / 状态记忆**全部由 `shared/datatable` 原生提供**，
> 并自动持久化到 `user_settings`（stateKey = `${tableId}_${viewMode}_table_state`）。
> 因此 V1.34 的「手写 flex 复刻 pinned-left」一段**作废**（仅保留为设计探索记录），
> 取而代之的是「引用原生 AG Grid 栈 + 后端 `grid` 端点喂 JSON:API」的落地形态。
> 原型仓 `ELN系统-Vue3` 的 `pinned[]` 实现**非线上真源**。

> **V2.1 修订（同日晚，P3 ELN 专属渲染）**：V2.0 的列定义里 owner/status/完成计数用
> `valueFormatter/valueGetter` **占位**成文本；P3 换成 **ELN 专属 `cellRenderer`**（负责人
> 色块+首字母、状态点+标签、进度条+计数、行菜单 kebab），并补齐 `rowMenu` 列。
> 见下方「P3 实际落地」。同时修正一条 V2.0 的种子硬约束：默认列状态必须**含 `rowMenu`**，
> 且选择列的 colId 是 `ag-Grid-ControlsColumn`（非 `checkbox`）—— 否则 `applyTableState`
> 的「自愈」分支（`columnsState.length !== columnDefs.length + 1`）会以 grid 运行态覆写存档、
> 把 `rowMenu` 列写丢（2026-10-07 实机排查）。

> **V2.2 修订（同日晚，访问权限列回旧版形态）**：P3 后「访问权限」列仍是 `valueFormatter`
> 输出的「N 人」计数，与**旧版**（原型 `ELN系统-Vue3` 与旧 addon blob 两处**逐字节一致**）
> 的「头像圆点堆叠 + `+N`」不一致。按用户要求「对齐旧版」，新增
> `renderers/members_renderer.vue`：浅底+深字头像（最多 3）+ 组用人形图标（`kind==='group'`）
> + `+N` 气泡，`title` = 成员名；调色板抽到 `renderers/avatar_palette.js`
> （blue `#DBEAFE/#2563EB`、green `#E7F7E9/#047857`、orange `#FCF2E3/#B45309`、
> purple `#E9DFF6/#6D28D9`、cyan `#E3F6F7/#0E7490`）。同时把「负责人」头像改为同一调色板
> （旧版两列本就用同一个 `avatarStyle`，避免一张表里出现两种头像语言）。
> ⚠ 后端 `members` **已截断为前 3 个**、`extra` 是余量 ⇒ 前端**不得**再按 `length` 推算隐藏数。

## Context
`/eln_project_list`（eln_ui addon 的 Vue 项目列表页，自绘表格）此前只有列宽持久化
（localStorage，`useColumnResize`）。用户要求对齐原生 `/projects` 的行为：
**列显隐选择能记住**，且**能钉住某些列**（参照原生 Manage columns 弹窗：
眼睛显隐 + 图钉钉列 + 拖拽排序 + 恢复默认）。

原生真源机制（`app/javascript/vue/shared/datatable/table.vue` + `modals/columns.vue`）：
- 列状态（显隐/钉住/顺序/宽度/排序/每页条数）**按用户存服务端**：
  `GET/PUT /user_settings/:key`（通用 per-user KV，`UserSettingsController`
  `find_or_initialize_by(key:)`，value 自由 JSON），key 形如 `<tableId>_<viewMode>_table_state`。
- 钉列依赖 AG Grid pinned 区：任意列可钉、可拖拽重排（vuedraggable）。

## Decision
1. **持久化走原生同一条端点**：前端 `GET/PUT /user_settings/eln_project_list_table_state`，
   存 `{ columnVisibility, pinnedUpTo }`。零后端新代码（端点本就是通用 KV）。
   变更即保存（toggleColumn / togglePinned，300ms 防抖）。
   - URL 基址由 payload 下发（`userSettingsUrl`），遵守「前端不写死宿主路由」铁律。
   - 原型独立跑（无 userSettingsUrl）自动跳过，行为不变。
   - 404/网络失败静默降级默认值（与原生 fetchTableState 的 catch 同口径）。
2. **钉列语义 = 「每列独立钉/取消，可同时钉多列」**（V1.34，复刻原生 ag-grid pinned-left）。
   原生 `shared/datatable/modals/columns.vue` 里每列一个图钉，点一下即在钉住集合里
   增删该列，多个钉住列归拢到表格最左、组内保持列序 —— 横向滚动时不动，未钉列从
   其下方穿过，钉区右缘有投影。我们的表格是手写 flex 网格（无 ag-grid pinned 容器），
   用两条 CSS 等价复刻：
   - 钉住列 `order:0` + `position:sticky; left:累积偏移` → 归拢最左且滚动不动；
   - 未钉列 `order:1` → 整组排到钉住区之后，z-index 低、从钉区下方穿过。
   `left` 偏移 = 行左留白(20px) + Σ(前面各钉住**可见**列宽 + gap 12px)，宽度真源 =
   useColumnResize 的 `widths`，拖宽时钉列偏移自动跟随。钉住区最后一个带 `pin-last`
   右投影（原生同款视觉信号）。恒钉列（check/选择列）`alwaysPinned`，不给图钉、不可取消
   （对齐原生 selectionColumnDef `pinned:'left'`）。
   - 数据模型：`pinned` 是**数组**（非 V1.33 的 `pinnedUpTo` 单锚点）。原因：单锚点
     只能表达「前缀」，无法复刻原生「任意多列」；数组即真源，且序列化 JSON 往返一致
     （reactive 的 Set 变更虽响应、但序列化要额外转换，且与持久化形态不一致）。
   - 列管理菜单分两组：钉住组 → `__pinned_sep__` 分隔线 → 未钉组（原生 pinnedSeparator
     同款）。分组依据用 `isPinned`（不看可见性）：钉住但暂时隐藏的列仍属钉住组，避免
     显示状态与真实状态相反（第二真源）。
   - 单元格底色走 `background-color:inherit`（.trow 补不透明底 `var(--color-card)`），
     hover/focused 行色自动同步到钉住单元格。
3. **不做**：列拖拽重排（需整表重写，另行立项）；筛选面板条件持久化
   （原生也不持久化 filters，且筛选已走 URL/服务端，深链可分享）。

## Consequences
-更容易：列显隐/钉列跨浏览器、换机器保留（服务端按用户）；未来若做「排序/每页条数
 持久化」只需往同一个 value 里加字段。
- 更容易：钉列偏移与列宽拖拽共用一份宽度真源，拖宽时冻结偏移自动跟随。
- 更难/代价（V1.33 遗留，V1.34 已收窄）：列顺序仍不可自定义（无 vuedraggable 重排）；
  但若只是「多钉几列」，现在已与原生观感一致 —— 这是用户本轮明确要的「复刻原生多列钉住」。
- ⚠ 旧存档迁移：V1.33 存的 `pinnedUpTo` 单锚点，升级后由 `prefixUpTo()` 转成等价的
  前缀集合（锚点及其左侧可见列），老用户升级**钉列不丢**；未知键/脏数据经
  `normalizePinned()` 剔除、恒钉列补回、顺序按列序重排，避免静默错位。
- ⚠ 踩坑记录（复用端点时必读）：
  1. **addon 是 engine**：宿主路由 helper 必须
     `Rails.application.routes.url_helpers.xxx` 全限定，裸调 `user_settings_path`
     直接 NameError → 整页 500。
     > ⚠️ 2026-10-09 辨析（ADR-0031 V2.0 实证）：本条其实是**另一类**失败 —— `user_settings_path`
     > 压根不存在（`only: %i(show update)` 无 collection 路由），runner 里同样 NameError。
     > 还有一类更隐蔽的：helper **存在于宿主 route set**，但 `isolate_namespace` 让 controller 的 `_routes`
     > 指向**引擎自己的空路由集**（eln_ui 无 `config/routes.rb`）⇒ 裸调抛
     > `UrlGenerationError (No route matches {controller:…})`，**runner 里却完全正常**。
     > 排查口诀：**controller 炸 / runner 好 ⇒ 先怀疑 route set，不是参数、也不是 `_recall`。**
  2. `resources :user_settings, only: %i(show update), param: :key` **没有 collection
     路由** ⇒ `user_settings_path` helper 不存在，只有 member 的 `user_setting_path(key)`。
     基址用占位 key 生成再剥尾巴：
     `user_setting_path('--KEY--').chomp('/--KEY--')` → `/user_settings`。
- 部署管线（同 ADR-0034 时代既有配方）：原型仓 `npx vite build --config vite.embed.list.config.js`
  （lib/IIFE 单文件，JS+CSS 都要更新）→ 拷入 addon assets → 容器 docker cp →
  Sprockets 单文件 compile → restart。

## V2.0 实际落地（引用原生 AG Grid 栈，非复制原型）

### 架构
- **引用而非复制**：`list.vue` 经 webpack alias `shared` 引入 `app/javascript/vue/shared/datatable/table.vue`，
  `eln_project_list.js` 入口沿用 `vue_teams_table.js` 的 `mountWithTurbolinks` 范式（内联，避免依赖宿主 packs 树）。
  单一真源，不复制原生代码。
- **后端 `grid` 端点**：`project_list_controller#grid` 复用现有 `ProjectListPayload#call` 的 `:projects` 行集合
  （ELN 项目∪文件夹，保留 ELN 已加的文件夹导航/定制列），包成 JSON:API 形状
  `{ data:[{id,type,attributes}], meta:{total_pages,total_count,filtered_count} }`，`shared/datatable` 即插即用。
- **列定义**：`columnDefs` 声明 ELN 16 列（name/code/status/owner/completed/tasksCompleted/members/...）。
  V2.0 时用 `valueFormatter/valueGetter` 占位渲染对象字段（owner/status），**P3 已换成 ELN 专属 `cellRenderer`**
  （负责人色块+首字母、状态点、进度条+计数、行菜单 kebab），见下「P3 实际落地」。

### 复用原生栈的硬约束（踩坑记录，必读）
1. **`tableId` 必须下划线**：`UserSetting` 模型校验 key 正则 `/\A[a-z0-9]+(?:_[a-z0-9]+)*\z/`，
   连字符会被拒（422），且 `stateKey` 拼出来即非法 ⇒ 用 `eln_project_list` 而非 `eln-project-list`。
2. **`:toolbar-actions` 必须非空**：`table.vue` 用 `v-if="Object.keys(toolbarActions).length"` 决定渲染 Toolbar；
   空对象 ⇒ Manage Columns 按钮永不出现（多列钉住入口消失）。传 `{ left:[], right:[] }` 即可触发。
3. **首次无存档 `tableState` 为 null**：`columns.vue#syncColumns` 会 `null.columnsState.forEach` 崩 ⇒
   弹窗空白。已用 `seed_eln_pl_state.rb` 给 `eln_project_list_active_table_state` seed 默认 **16 列**状态
   （`ag-Grid-ControlsColumn` + name 预钉）。⚠ 种子的 colId **必须逐一等于 `columnDefs.field`**（选择列的真实
   colId 是 `ag-Grid-ControlsColumn`，不是 `checkbox`），且总数须 = `columnDefs.length + 1`；否则触发下述自愈覆写。
6. **列集合/顺序的「自愈」覆写**：`table.vue#applyTableState` 在 `columnsState.length !== columnDefs.length + 1`
   时会调 `saveTableState()` 用 grid 运行态覆写存档。新增列（如 `rowMenu`）后若种子未同步，会被这次自愈
   写成「新运行态」（若当时该列尚未渲染/被虚拟化掉，就会**丢列**）。修法：改列后同步更新种子并删档重 seed。
4. **构建**：宿主 `config/webpack/webpack.config.js` 加 `shared` alias（路径需 `..','..'`，否则解析到
   `config/webpack/app/...` 报 module not found）+ 注册 `eln_project_list` entry；用单 entry 临时配置只编目标，
   避免全量重编拖崩 Docker（10-07 事故）。
5. **验证脚本坑**：Manage Columns 弹窗图钉 `@click` 在**内部 `<i>`**，不在外层 `data-e2e` 的 div（事件不向下冒泡）；
   钉住表头在 AG Grid v32 的 `.ag-pinned-left-header`（非 `.ag-pinned-left-cols-container` 那个 body 容器）。

### Consequences（V2.0 视角）
- 多列钉住 / 列重排 / 显隐 / 排序 / 每页条数 全部**免费**获得并自动持久化（服务端按用户），无需自写任何状态逻辑。
- 与原生 `/projects` 行为**完全一致**（同一套 `shared/datatable`），后续维护成本最低。
- 代价：ELN 定制渲染（负责人色块、完成计数、行菜单）需以 `cellRenderer` 形式挂到 `columnDefs`，
  不能直接改原生 `shared/datatable` 内部（那是原生代码，改了会 diverge）。P3 在该边界内做 ELN 专属渲染。

## P3 实际落地（ELN 专属 cellRenderer）

在「不复制原生、只挂 `cellRenderer`」的边界内，为 ELN 行集合写了 5 个专属渲染器
（`addons/eln_ui/app/javascript/vue/eln_project_list/renderers/`）：

| 渲染器 | 列 | 逻辑 |
|---|---|---|
| `owner_renderer.vue`     | 负责人     | 头像圆点（共用 `avatar_palette.js`）+ 姓名/邮箱 |
| `status_renderer.vue`    | 状态       | 圆点（色随状态）+ 中文标签（未开始/进行中/已完成…） |
| `progress_renderer.vue`  | 已完成实验 / 已完成任务 | 进度条 + `已完成/总数` 计数（同一组件，`cellRendererParams` 传字段名） |
| `members_renderer.vue`   | 访问权限   | **对齐旧版**：浅底+深字头像（最多 3）叠压 + `+N`（旧版语义，非「N 人」计数）；组 `kind==='group'` 画人形图标；`title` = 成员名 |
| `row_menu_renderer.vue`  | 行菜单 kebab | 读 `params.data.actions`（Hash，ELN payload 算好的 `{key:{enabled,method,url}}`），按 `enabled` 过滤成菜单；GET 型走 MenuDropdown 的 `url` 跳转，变更型（edit/move/archive/export/delete）走 `emit:rowAction` + axios，成败都 `reloadTable`（静默降级，绝不让一次请求失败崩整页） |

- `avatar_palette.js` 是 owner / members 两列共用的头像调色板与描边/`+N` 色（**单一真源**，
  别在各渲染器里各写一份 hex）。
- 挂接方式与原生 `projects/list.vue` 一致：`cellRenderer: <importedComponent>`（组件对象，非字符串名）。
- addon→host 依赖经 webpack alias：`shared`（`app/javascript/vue/shared`）与 `custom_axios`
  （`app/javascript/packs/custom_axios.js`）。**相对路径 `../../../packs/...` 在 addon 内会解析到 addon 自己**，
  故必须用 alias，不能用相对路径。
- 行菜单列表项实测（只读行，无 manage 权限）：`访问权限 / 移动 / 导出 / 评论 / 动态`（编辑/归档/删除按 gate 隐藏，符合预期）。

## Verification
- `verify_project_list_cols.rb` / `verify_project_list_multipin.rb`（真会话）：页面 200 + 引用新
  bundle digest + payload 含 `userSettingsUrl` + served bundle 含 pin/持久化标记 +
  `user_settings` 带 CSRF 的 PUT/GET 往返成功（写入 `pinned:['name','status']` 读回一致）
  + 清理。ALL PASS。
- `_pl_multipin.js`（Playwright 真浏览器，窄视口 900px 逼出横向溢出）：① 列管理菜单可开；
  ② 重置历史钉列后 on 数归 0；③ **同时钉 name+status，菜单内两枚图钉均 `on`（多列并存）**；
  ④ 表头 CSS：钉住列 `position:sticky;order:0`、未钉列 `order:1`；⑦ 横向滚动 500px 后，
  钉住列( check/name/status ) `Δleft=0`、未钉列( id/owner ) `Δleft=-500` —— 与原生
  ag-grid pinned-left 行为一致。页面无 console/pageerror。

### V2.0 验证（引用原生 AG Grid 栈，Playwright 真浏览器）
- `_pl_grid_v2.js`：① AG Grid 渲染 ELN 数据；② `/eln_project_list/grid` 合法 JSON:API
  （`data[].type=project`、`meta={total_pages,total_count,filtered_count}`）；③ 开 Manage Columns 弹窗 →
  点 status + code 内部 `<i>` 图钉，钉住区列数 = 4（checkbox+name+status+code）；
  ④ 刷新后钉住区仍 4 列，且 `GET /user_settings/eln_project_list_active_table_state` 返回
  `columnsState` 含 `["ag-Grid-ControlsColumn","name","code","status"]`（pinned 列）—— **多列钉住 + 跨会话持久化双向验证通过，页面无 console/pageerror**。
- 踩坑验证：曾因 `tableId` 用连字符导致 422（pin 静默不存）；曾因 `toolbarActions` 为空导致 Manage Columns
  按钮不渲染；曾因首次无存档 `tableState=null` 导致弹窗崩；均已修复（见上「硬约束」）。

### P3 验证（ELN 专属渲染器，Playwright 真浏览器）
- `_pl_p3_verify.js`（视口 2600px 逼出全部 16 列、含最右 `rowMenu`）：
  ① 四种渲染器全部落地 —— 负责人头像 24 个（12 行×若干内层元素，样本首字母 "HR"）、状态点 12、
  进度条 12、行菜单 kebab 6（= 可见行数）；表头 colId 共 16，**末列是 `rowMenu`**；
  ② 点首行 kebab → 菜单展开，列出 `访问权限 / 移动 / 导出 / 评论 / 动态`；
  ③ 页面无 console/pageerror。
- 回归：`_pl_grid_v2.js` 复跑 —— 多列钉住（钉 status + code）钉住区 = 4 列，刷新后仍 4 列，
  服务端存档含 `["ag-Grid-ControlsColumn","name","code","status"]`。**P3 未破坏钉列持久化**。
- 渲染器落地排查（`_pl_rowmenu_probe.js`）：`rowMenu` 列一度**整个消失**（表头 colId 无 rowMenu）。
  根因：默认列状态种子（`seed_eln_pl_state.rb`）早于 `rowMenu` 列产生、且用了错误的 controls colId `checkbox`，
  于是 `applyTableState` 判定 `columnsState.length(15) !== columnDefs.length+1` 触发**自愈**，
  用 grid 运行态覆写存档 —— 彼时运行态已丢失 rowMenu。修法：种子 colId 与 `columnDefs.field` 对齐
  （含 `ag-Grid-ControlsColumn` 与 `rowMenu`，共 16），并删档重 seed。
