# ADR-0038: 项目列表（eln_ui）V1 全功能补缺批次二

> 收藏星标列 · 文件夹行专属视觉 · 批量选择/批量操作 · AG Grid 主题美化
> 接续 ADR-0035（原生 AG Grid 栈选型）+ ADR-0037（四项判据硬伤）

## Status

Proposed

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
- **唯一后端缺口**：`project_list_payload.rb` 的 `project_row`(L335) 与 `folder_row`(L407) 均
  **硬编码 `starred: false`**；`Project` 模型与 `config/routes.rb` 均无 star 设施 → 收藏列无数据源、无切换端点。
- **宿主 DataTable 已具备批量能力可复用**：`shared/datatable/table.vue` 支持 `withCheckboxes` prop
  （L160 定义、L350-353 接入 `rowSelection`），选中变化 `emit('selectionChanged', selectedRows)`
  （L770/783/796）。当前 `list.vue` 未开启该 prop。
- 旧手写 `eln_project_list.css` 注释自陈「仅作兼容保留，实际样式由宿主 Tailwind + AG Grid 主题承担」→
  手写视觉细节整体丢失，落入 AG Grid 默认主题。

## Decision

对四项缺失功能分别立项，原则：**复用宿主 DataTable 既有能力 + 后端最小切口 + 不推翻 ADR-0035 栈选型**。

---

### 0038-A 收藏/星标列（favorite / star）

**上下文**：V1 原型与旧栈均有收藏星标，可一键标星 + 按收藏筛选；当前完全缺失且后端硬编码 false。

**决策**：
1. **数据源**：`ProjectListScope` 增加 `starred` 投射——优先复用宿主 `projects.starred` 列（若 schema 无则
   加迁移 `add_column :projects, :starred, :boolean, default: false`）；scope 按当前用户判定。
2. **payload**：删 `project_row`/`folder_row` 两处 `starred: false`，改由 row 真实属性透传
   （`addons/eln_ui/app/services/scinote/eln_ui/project_list_payload.rb:335,407`）。
3. **切换端点**：`ProjectListController` 新增 `toggle_star` 动作（`PATCH /eln_project_list/:id/star`），
   engine 注册路由；前端 `PATCH` 后乐观更新该行 `starred`。
4. **前端列**：在 `name` 列后插入 `favorite` 列（宽 ~46px），`cellRenderer` = 新
   `renderers/favorite_renderer.vue`（星标图标 + 点击切换 + 乐观态），folder 行不渲染星标。

**取舍**：
- 得：补齐 V1 收藏能力，与宿主项目列表语义一致。
- 舍：需新增路由 + 迁移（若 schema 无 `starred`），改动面略大于「纯前端假星」——但假星不可持久，否决。

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
- **后端最小切口**：仅 `ProjectListScope` 加 `starred` 投射 + 一处 `toggle_star` 端点 + payload 两行去硬编码；
  行装配与分页逻辑零改动（已复用）。
- **前端复用宿主能力**：批量走 `withCheckboxes`、列管理走原生 DataTable，不重造轮子。
- **风险**：0038-D 的 CSS override 需真机核验（AG Grid 节点类名随版本变）；0038-A 若 schema 无 `starred`
  需补迁移，须先 `git grep` 确认。
- **不在本 ADR**：页面级「权限设置」入口（属 access_control addon，单独推进）；行菜单 7 项已在 07e0fc1d4 保留。

## 关联

- ADR-0035（原生 AG Grid 栈选型，不可推翻）｜ADR-0037（批次一判据硬伤）｜ADR-0032（资源中心，同源手写→原生迁移范式）
- 代码真源：`addons/eln_ui/app/javascript/vue/eln_project_list/` ｜ `addons/eln_ui/app/services/scinote/eln_ui/project_list_*.rb`
  ｜ `app/javascript/vue/shared/datatable/table.vue`
