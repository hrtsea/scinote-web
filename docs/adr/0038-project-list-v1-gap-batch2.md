# ADR-0038: 项目列表（eln_ui）V1 全功能补缺批次二

> 收藏星标列 · 文件夹行专属视觉 · 批量选择/批量操作 · AG Grid 主题美化
> 接续 ADR-0035（原生 AG Grid 栈选型）+ ADR-0037（四项判据硬伤）

## Status

Accepted（A/B/C/D 四项均已实现并验证）

## Context

`07e0fc1d4`（2026-10-09）把 `eln_project_list` 从旧手写 Vue 应用迁到宿主原生 AG Grid 栈，并恢复
四项判据硬伤（每页档位 / 操作列名 / 卡片视图 / 状态口径）。该提交本质是**迁移 + 最小恢复**，不是
V1 全量功能迁移——旧栈 `3d76f9d51` 手写应用里更多功能在迁移中被**丢弃或留待补做**。

证据（均对 HEAD 实证）：

- 前端 `list.vue` 当前定义 **16 列**（name/code/status/startDate/due/owner/completed/tasksCompleted/
  members/commentsCount/description/createdAt/updatedAt/archivedOn/rowMenu），**无 favorite/star 列、
  未启用 `rowSelection`**（grep 实证 `addons/eln_ui/app/javascript/vue/eln_project_list/list.vue:105-162`）。
- 后端 **行装配未退化**：`ProjectListRows`（`project_list_rows.rb`）+ `ProjectListScope`
  （`project_list_scope.rb`，workbench 也共用）在 `grid` 端点被完整复用。
- **后端缺口**：`project_list_payload.rb` 的 `project_row` 与 `folder_row` 均**硬编码 `starred: false`**。
  ⚠ **修订（2026-10-09）**：宿主 `app/` 层面 `Project` **已有** per-user 收藏设施——`Favoritable` concern
  （`has_many :favorites, as: :item` + `favorite!/unfavorite!`）+ `public.favorites` 多态表 +
  `POST /projects/:id/favorite|unfavorite` 端点 + `shared/datatable/renderers/favorite.vue`。eln payload
  只是**没接上**宿主这套（并非宿主无此能力）。
- **宿主 DataTable 已具备批量能力可复用**：`shared/datatable/table.vue` 支持 `withCheckboxes` prop
  （L160 定义、L350-353 接入 `rowSelection`），选中变化 `emit('selectionChanged', selectedRows)`
  （L770/783/796）。当前 `list.vue` 未开启该 prop。
- 旧手写 `eln_project_list.css` 注释自陈「仅作兼容保留，实际样式由宿主 Tailwind + AG Grid 主题承担」→
  手写视觉细节整体丢失，落入 AG Grid 默认主题。

## Decision

对四项缺失功能分别立项，原则：**复用宿主 DataTable 既有能力 + 后端最小切口 + 不推翻 ADR-0035 栈选型**。

---

### 0038-A 收藏/星标列（favorite）— ✅ 已实现（含一次架构修订）

**上下文**：V1 原型与旧栈均有收藏星标，可一键标星；当前完全缺失且后端硬编码 false。**关键发现**：
宿主 `/projects` 页**原生就有 per-user 收藏**——`public.favorites` 多态表（user/team/item）+
`Favorite` 模型 + `POST /projects/:id/favorite|unfavorite` 端点（`resources :projects` member）+
宿主 `shared/datatable/renderers/favorite.vue` 渲染器；`Project` 经 `Favoritable` concern 自带
`favorite!`/`unfavorite!`/`favorites` 关联。

**决策（修订后）**：
1. **数据源**：**直接复用宿主 `favorites` 表**，不自建表。`payload` 一次
   `::Favorite.where(user: current_user, item_type: 'Project').pluck(:item_id)` 得当前用户收藏的项目 id 集合
   （memoize），`favorite: ids.include?(project.id)`。
2. **切换端点**：**复用宿主** `POST /projects/:id/favorite|unfavorite`；行内下发
   `urls: { favorite:, unfavorite: }`（`favorite_project_path` / `unfavorite_project_path`）。
3. **前端列**：`name` 前插 `favorite` 列（宽 46px），`cellRenderer` = **宿主原生 `FavoriteRenderer`**
   （同一份数据 + 同一外观）；渲染器经 `params.dtComponent.$emit('updateFavorite')` 冒泡，`list.vue` 的
   `updateFavorite` POST 对应 url 后 `reloadTable()`。folder 行 `favorite:false` 且无 `urls.favorite`
   ⇒ 宿主渲染器自动隐藏按钮。

**❗️ 架构修订记录（2026-10-09）**：本 ADR 初稿曾计划「`projects` 加 `starred` 全局列 / 自建
`eln_ui_project_stars` 表 + `toggle_star` 端点」。实现中发现宿主已有原生 `favorites` 机制 ⇒ 自建表会导致
`/projects` 与 `/eln_project_list` **两套收藏数据分裂**（在 A 页收藏的不在 B 页显示），且用户明确
「原生就有收藏星标」。故**改为复用宿主**：撤销自建表（新增迁移 `20261009171000_drop_eln_ui_project_stars`）、
撤销 `toggle_star` 端点与 `PATCH /eln_project_list/:id/star` 路由、删除自写 `favorite_renderer.vue`
（改用宿主渲染器）。**教训**：动手前先 grep 宿主是否已有同义机制，避免重复造轮子。

**取舍**：
- 得：与 `/projects` 收藏状态**单一数据源**（同表 / 同外观 / 同端点）；零新增表、零新增迁移、零新增端点；
  前端直接复用宿主渲染器与宿主端点。
- 舍：eln 列表收藏外观 = 宿主外观（不可独立定制）——这正是期望（一致性优先）。切换后整表
  `reloadTable()`（与宿主 `projects/list.vue` 同款，非局部刷新）——代价是多一次请求，可接受。

---

### 0038-B 文件夹行专属视觉（folder badge / icon）

**上下文**：旧栈 folder 行有专属徽章（项目数｜文件夹数）+ 图标 + 下钻链接；新栈 16 列对所有行同渲染，
folder 行无视觉区分，`Lists::ProjectAndFolderSerializer#folder_info` 已下发但未利用。

**决策**：
1. `name` 列 `cellRenderer`（现有 `ElnNameRenderer` 或新建 `ElnNameFolderRenderer`）按 `row.folder` 分流：
   folder 行渲染文件夹图标 + `folder_info` 徽章（`{project_count} 个项目 · {folder_count} 个子文件夹`）+ 下钻链接。
2. 复用 payload 已下发的 `folder_info`（确认 `project_list_payload.rb` 行装配含该字段；缺失则补）。
3. folder 行可选加轻微行底色，强化层级感。

**取舍**：
- 得：恢复 V1 文件夹辨识度，下钻体验无缝。
- 舍：name 列 renderer 需分支逻辑（folder/project 双形态），略微增复杂——但比「两列两套渲染」更省。

---

### 0038-C 批量选择 + 批量操作（batch）— ✅ 已实现（复用宿主内建批量条）

**上下文**：旧栈支持多选 + 批量（移动/归档/删除等）；新栈 `list.vue` 未传 `actionsUrl`，无批量条。

**关键发现**：宿主 DataTable **内建批量操作条**——`table.vue` 在 `selectedRows.length > 0 && actionsUrl` 时
渲染 `<ActionToolbar :actionsUrl :actionsMethod :params @toolbar:action="emitAction">`（`table.vue:100-105`）；
选中集合以 `items=JSON.stringify([{id,type}])` POST 到 `actionsUrl` 拿「公共可用动作」，点击再
`$emit(action.name, action, selectedRows)`（`table.vue:785-786`）。即**无需自建批量条**（原计划「自建批量
toolbar」属再次重复造轮子）。另 `res_center_controller.rb:112` 已有同款先例（复用宿主 `actions_toolbar_*`）。

**决策（修订后）**：
1. **动作端点**：新增 `POST /eln_project_list/actions`（`ProjectListController#actions`），**复用宿主
   `Toolbars::ProjectsService`** 生成「选中集合上可用的公共动作」+ 逐项权限判定（`can_archive_project?` /
   `can_delete_project_folder?` / `can_manage_team?` …），与原生 `/projects` 批量条**同一真源**。
   项目集合走 `scoped_projects`（含 team + `readable_by_user`），文件夹走 `current_team.project_folders`。
   ⚠ 原生 `projects#actions_toolbar` 按 `type=='projects'/'project_folders'`（**复数**）分流，而 ELN 行
   type 是单数 ⇒ 端点内做映射（前端不必改 type 契约）。
2. **只暴露已接线动作**：`allowed = %w[archive restore delete_folders move]` 白名单过滤。宿主 Service 还会
   返回 `edit/access/comments/activities/export`，其中单读类动作由行 kebab 菜单承担，这里不重复暴露，
   以免 ActionToolbar 渲染出「点了没反应」的死按钮。
3. **前端**：`list.vue` 传 `:with-checkboxes="true"` + `:actions-url="/eln_project_list/actions"`，监听
   `@archive/@restore/@delete_folders/@move`（`emitAction` 按 name 重发，签名 `(action, rows)`）：
   - `archive`/`restore` → `POST action.path { project_ids: rows.map(id) }`
   - `delete_folders` → `POST action.path { project_folder_ids: rows.map(id) }`
   - `move` → 复用**宿主 MoveModal**（`host/projects/modals/move.vue`）；⚠ `selectedObjects.type` 映射成端点
     认的**复数**（`project_folders`/`projects`），因为 ELN 行 type 是单数（见 `project_folders#move_to`）。
4. 操作完成后 `reloadTable()`（默认清空选择）。

**取舍**：
- 得：批量条 UI **零自研**（宿主 `ActionToolbar`）；动作与权限判定复用宿主 `Toolbars::ProjectsService`
  （单一真源，谁改原生批量动作语义这边自动跟随）。
- 舍：需新增一个薄端点（做单/复数 type 映射 + `allowed` 过滤）；`move` 需从选中行的单行 `actions.move`
  取 `url`/`folders_tree_url`（批量 action 只给模态内容 path）。
- **未做**：批量 `export`（ADR-C 未点名，且需 limit modal，另立）；单读动作（access/comments/activities）
  仍走行 kebab 菜单。

**端到端验证（真实 HTTP POST /eln_project_list/actions）**：单选项目 → `["move"]`（该用户对项目无
archive/delete 权限）；单选文件夹 → `["move","delete_folders"]`；混选 → 交集 `["move"]`；空 items → `[]`。
权限过滤与类型交集均正确。

---

### 0038-D AG Grid 主题美化（UI 不恶化）— ✅ 已实现（含一次方案修订）

**上下文**：迁移后原以为落入「AG Grid 默认主题」，真机核验后修正认知 —— 宿主**已有**全局网格主题
  `app/assets/stylesheets/shared/ag_table.scss`（用 SciNote token `--sn-*` 统管表头底/悬浮/选中/内边距/边框），
  栅格并非默认皮肤。真正肉眼可见的「恶化」是**列被压扁**：宿主 `shared/datatable` 在**无持久化列状态**时
  调用 `gridApi.sizeColumnsToFit()`（`table.vue#onGridReady`）；本页 16 列、各列 `minWidth` 之和已超视口，
  size-to-fit 把非 `name` 列一律压到 `minWidth`（宿主默认 110）⇒ 表头截断为「开始日…」「已完成…」。

**决策**：
1. **列宽（主修）**：`list.vue` 的列改为经 computed `columnDefs` 注入 `suppressSizeToFit: true`
   —— AG Grid 官方属性「size-to-fit 时固定该列宽」。此后列按定义宽度渲染、超视口走横向滚动（宽表正常行为）。
2. **主题（微调，不另起皮肤）**：`addons/eln_ui/app/javascript/vue/eln_project_list/styles/eln_project_list.scss`，
   scoped 到 `#eln-project-list`，**只补宿主 `ag_table.scss` 未覆盖的点**：
   - `--ag-alpine-active-color` / `--ag-checkbox-checked-color` 对齐 `var(--sn-science-blue)`（#3B99FD）
     —— 宿主未设该 alpine 变量，否则落 AG Grid 默认 #2196f3，复选框/选区会与全站品牌色分叉；
   - 空数据 / 加载遮罩文案（宿主未定义）。
   其余（表头底、行高、悬浮、选中、内边距、边框、字体）一律交宿主统一主题，**不覆盖、不重复**。
3. **样式承载方式并入 webpack**：SCSS 由 `packs/eln_project_list.js` import → `MiniCssExtractPlugin` 抽取为
   `app/assets/builds/eln_project_list.css` → 登进 `assets.precompile`（`addons/eln_ui/.../engine.rb`）→ 视图用
   `stylesheet_link_tag 'eln_project_list'`。**退休**原型 blob `eln_vue3/eln_project_list.css`（连同其旧
   `:root` token 一起删；实测新 SFC 不依赖那些变量），消除「项目列表 CSS 走 Sprockets 特殊路径」这一历史例外。

**取舍**：
- 得：在不动宿主共享主题、不引入新 UI 框架的前提下消除「表头截断」这一实打实的观感缺陷；eln 表与全站表格外观一致。
- 舍：不再追求「V1 prototype 独有皮肤」——生产品牌色是 `--sn-science-blue`（与 ELN 状态色/卡片色一致），
  强行套 V1 的 `--color-primary #2563EB` 反而与全站分叉；故 ADR 原计划的「整套变量覆盖」被**否决**。
- ⚠ **已知遗留**：`suppressSizeToFit` 只对**新**列状态生效；若某用户已存过「被压扁」的列状态
  （宽度 110），`applyColumnState` 仍会还原旧宽度（宿主无列状态迁移机制）。本次已清库侧 `user_settings`
  三条 `eln_project_list*table_state`；宿主 DataTable 的列状态迁移属共享组件改动，单独立项。

---

## Consequences

- **恢复**：V1 四项功能（收藏 / 文件夹视觉 / 批量 / 美化）补齐，项目列表体验回到 V1 水准且架构更一致。
- **后端最小切口（修订）**：0038-A payload 一处改用宿主 `Favorite` 查询（替换硬编码 `starred`）+ 行内下发
  `urls.favorite/unfavorite`（**零新增表 / 迁移 / 端点**）；0038-B 修 `folder_info` 计数来源；0038-C 新增一个
  薄端点 `POST /eln_project_list/actions`（复用宿主 `Toolbars::ProjectsService`，做单/复数 type 映射 +
  `allowed` 过滤）。行装配与分页逻辑零改动（已复用）。
- **前端复用宿主能力**：收藏走宿主 `FavoriteRenderer`、批量条走宿主内建 `ActionToolbar`、批量移动走宿主
  `MoveModal`、列管理走原生 DataTable、网格外观走宿主 `shared/ag_table.scss` 主题 —— 不重造轮子
  （C 项原计划的「自建批量 toolbar」、D 项原计划的「整套 AG Grid 变量覆盖」均已被否决）。
- **真机核验已完成**：D 项经 headless Chromium（现签 Warden 会话）实测 —— 列宽恢复定义值
  （status 130 / owner 180 / completed 140 …，此前统一被压到 110）、表头不再截断、`--ag-alpine-active-color`
  解析为 #3B99FD；卡片视图文件夹徽章、收藏列星标、`Show: 全部/20 条` 档位均可见。
- **不在本 ADR**：页面级「权限设置」入口（属 access_control addon，单独推进）；行菜单 7 项已在 07e0fc1d4 保留。

## 关联

- ADR-0035（原生 AG Grid 栈选型，不可推翻）｜ADR-0037（批次一判据硬伤）｜ADR-0032（资源中心，同源手写→原生迁移范式）
- 代码真源：`addons/eln_ui/app/javascript/vue/eln_project_list/` ｜ `addons/eln_ui/app/services/scinote/eln_ui/project_list_*.rb`
  ｜ `app/javascript/vue/shared/datatable/table.vue`
