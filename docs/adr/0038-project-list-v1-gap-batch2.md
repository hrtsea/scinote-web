# ADR-0038: 项目列表（eln_ui）V1 全功能补缺批次二

> 收藏星标列 · 文件夹行专属视觉 · 批量选择/批量操作 · AG Grid 主题美化
> 接续 ADR-0035（原生 AG Grid 栈选型）+ ADR-0037（四项判据硬伤）

## Status

Accepted（A/B 已实现并验证；C/D 待做）

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

### 0038-C 批量选择 + 批量操作（batch）

**上下文**：旧栈支持多选 + 批量（移动/归档/删除等）；新栈未开启 `rowSelection`，无批量条。

**决策**：
1. `list.vue` 的 `<DataTable>` 加 `:with-checkboxes="true"`（宿主已支持，见 `table.vue:160`）。
2. 监听 `@selectionChanged`，维护 `selectedRows`；选中数 > 0 时顶部浮现**批量操作条**（ batch toolbar）。
3. 批量动作复用现有行级能力端点：移动至文件夹 / 归档 / 删除，入参由 `selectedRows` 的 id 集合批量提交。
4. 批量条 UI 遵循宿主 `shared` 既有批量模式（参考 `app/javascript/vue/*` 中 `withCheckboxes` 使用方）。

**取舍**：
- 得：复用宿主 DataTable 多选，零自研选择框架；与全局交互一致。
- 舍：需自建批量操作条（宿主 DataTable 不内置批量动作 UI）——属必要薄封装。

---

### 0038-D AG Grid 主题美化（UI 不恶化）

**上下文**：迁移后落入 AG Grid 默认主题（白底/固定行高/无品牌色），较旧手写视觉落差明显；原 css 自称
「仅兼容保留」，等于放弃美化。

**决策**：
1. 新增 `addons/eln_ui/app/assets/stylesheets/eln_project_list.scss`（取代「仅兼容保留」的 css），
   用 **scoped override** 覆盖 AG Grid 主题变量与关键节点：品牌主色、行高/字号、表头、空状态、hover、
   卡片视图间距（`.eln-card`）。
2. 在 `packs/eln_project_list.js` 引入该 scss，并登记 `assets.precompile`（生产 `assets.compile=false`）。
3. 不引入新 UI 框架，只覆盖 AG Grid CSS 变量 + 少量节点样式，确保与宿主 Tailwind 视觉协调。

**取舍**：
- 得：在不推翻原生栈前提下，把视觉拉回 V1 手写水准甚至更好（统一主题）。
- 舍：需维护一份覆盖样式（AG Grid 升级时可能需同步）——但比「回退手写表格」代价小得多。

---

## Consequences

- **恢复**：V1 四项功能（收藏 / 文件夹视觉 / 批量 / 美化）补齐，项目列表体验回到 V1 水准且架构更一致。
- **后端最小切口（修订）**：0038-A payload 一处改用宿主 `Favorite` 查询（替换硬编码 `starred`）+ 行内下发
  `urls.favorite/unfavorite`；**零新增表 / 迁移 / 端点**（复用宿主）。0038-B 修 `folder_info` 计数来源。
  行装配与分页逻辑零改动（已复用）。
- **前端复用宿主能力**：收藏走宿主 `FavoriteRenderer`、批量走 `withCheckboxes`、列管理走原生 DataTable，不重造轮子。
- **风险**：0038-D 的 CSS override 需真机核验（AG Grid 节点类名随版本变）。
- **不在本 ADR**：页面级「权限设置」入口（属 access_control addon，单独推进）；行菜单 7 项已在 07e0fc1d4 保留。

## 关联

- ADR-0035（原生 AG Grid 栈选型，不可推翻）｜ADR-0037（批次一判据硬伤）｜ADR-0032（资源中心，同源手写→原生迁移范式）
- 代码真源：`addons/eln_ui/app/javascript/vue/eln_project_list/` ｜ `addons/eln_ui/app/services/scinote/eln_ui/project_list_*.rb`
  ｜ `app/javascript/vue/shared/datatable/table.vue`
