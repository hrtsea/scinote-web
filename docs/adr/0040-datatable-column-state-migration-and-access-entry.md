# ADR-0040: 宿主 DataTable 列状态迁移 + access_control 页面级入口（调研）

> 接续 ADR-0038-D（列状态迁移「单独立项」）+ ADR-0037/0038/0039（eln_ui 项目列表 V1 补缺）

## Status

- **第一部分（宿主列状态迁移）：Accepted**（`shared/datatable/table.vue` 加列签名自愈合，已真机双向验收）。
- **第二部分（access_control 页面级入口）：Proposed / 待裁决** —— 现状调研 + 语义分叉，**未动代码**。

## Context

### A. 宿主列状态迁移

ADR-0038-D 已知遗留：宿主 `shared/datatable/table.vue` 把列布局持久化到 `user_settings`
（key = `${tableId}_${currentViewMode}_table_state`），但**列结构变化后旧状态不做迁移**，
表现为「新增列被抑制 / 已删列残留为隐藏列」。上一批次（加 favorite 列）时一度需**手工清 DB**
才能让新列出现，且此后仍可能复发 —— 属于共享组件级缺陷，故单独立项。

实证（对 HEAD）：

- 状态键：`table.vue#stateKey()` → `${tableId}_${currentViewMode}_table_state`；读写走
  `user_setting_path(stateKey)`（`fetchTableState` / `saveTableState`）。
- 旧协调逻辑（`applyTableState`，改前 line 581-587）：仅当
  `tableState.columnsState.length !== columnDefs.length + 1` 时才**重存**一次，**不修正**新列的顺序/可见性；
  长度相同但「列身份」变了（改名/换列）时**完全不触发** ⇒ 旧状态静默压制新布局。
- 运行态证据：`user_settings` 里 `eln_project_list_active_table_state`（user_id=1）的
  `columnsState` 首列是 **`ag-Grid-ControlsColumn`**（AG Grid v32 的行选择/控件列，**运行时追加、
  不在 columnDefs 内**）。

### B. access_control「页面级权限设置入口」

调研结论（全仓 grep，无一凭记忆）：

- **access_control addon 只有两个 UI 面**，且**都是单项目级**（都需 `@project`，列表页无当前项目）：
  1. `projects/:project_id/visibility_matrix` —— 成员 × 实验可见性矩阵
     （`addons/access_control/app/controllers/.../visibility_matrix_controller.rb`；路由 `config/routes.rb:399-409`）；
  2. `access_permissions/projects/:id` —— 项目成员访问 CRUD。
- **visibility_matrix 的唯一入口**在 `app/views/experiments/index/_header.html.erb:22-23`：
  **项目内实验页**页头（`content-header`）的一个 `btn btn-outline-primary` 链接，门控
  `can_manage_project_users?(@project)`。**不是**列表页入口。
- 原生 `/projects`（列表页）**没有**任何页面级权限入口（grep 无命中）。
- **ELN 列表页的行级权限入口其实已经在了**：`eln_ui` payload 的 `row_actions` 早给每个项目行下发
  `access`（`project_list_payload.rb:37,596,630`，`ACTION_KEYS` 含 `access`；落点
  `access_permissions_project_path_of(project)` → `/access_permissions/projects/:id`；门控
  `can_manage_team? || can_read_project?`，与原生 `Toolbars::ProjectsService#access_action` 同源）；
  行菜单 `ElnRowMenuRenderer` 的 `labelMap` 已映射 `access: '访问权限'`。

⇒ **「页面级」在代码里没有原生对应物**：两条 access UI 都锚定单个项目，列表页（一层平铺、无当前项目）
放不下「页面级」权限入口。语义存在真分叉（见下）。

## Decision

### A. 宿主列状态迁移 —— 列签名（colSig）自愈合，不做一次性 DB 清除

在 `shared/datatable/table.vue` 引入**列身份签名**并以「集合不符即作废」自愈：

- `colSignature()`：`columnDefs` 的 `colId||field` 集合，排序后 `'|'` 连接 —— 列结构指纹。
- `storedSignature(state)`：已存 `columnsState` 的 `colId` 集合，**排除运行时列**
  `['checkbox','ag-Grid-ControlsColumn']` 后排序连接。
  - ⚠ 本 ADR 实现时**踩坑并已修**：首版只排除 `'checkbox'`，而 AG Grid v32 实际列 id 是
    `ag-Grid-ControlsColumn` ⇒ 签名恒不等 ⇒ **每次加载都判 stale** ⇒ 用户列定制永不持久。
    修法：排除集合补上 `ag-Grid-ControlsColumn`。
- `staleState(state)`：`storedSignature(state) !== colSignature()`。
- `fetchTableState()`：读到状态后若 `staleState` 为真 ⇒ `tableState = null`，**不 applyColumnState**，
  改由 `columnDefs` 驱动默认布局；否则照常还原（`currentViewRender` / `perPage` / `order`）。
- `saveTableState()`：写出的 `tableState` 附 `colSig: colSignature()`，供下次比对。

**为什么不选「一次性清 DB」**：清库只治当下（且要点名每个用户），下一轮改列即复发；签名自愈
**面对任何未来的增/删/改名列都自动生效**，且**只重置真正变过列的表**（`colSig` 一致的表零影响）。
老状态无 `colSig` 也不误伤 —— `staleState` 用「列集合是否一致」判定，集合未变则保留。

### B. access_control 页面级入口 —— 决策待用户裁决（三选一，见下）

不擅自开工：三条路线对交互与职责的影响不同，先落调研与取舍，选定后再实现。

## Consequences

### A（已实施）

- **得**：列结构演进（新增/删除/改名）后旧列状态**自动作废、无感重建**；不再需要任何手工清库；
  非 ELN 表（`colSig` 一致）行为**逐字节不变**。
- **舍**：每次加载多一次 O(列数) 的集合比较（可忽略）；`applyTableState` 里旧的「长度不符则重存」
  保留但已基本被签名逻辑覆盖（不删，避免扩大改动面）。
- 🔴 **部署约束（重要）**：本环境**全量 webpack（~110 entry）会打爆 Docker API（全 500）**，
  只能**定向构建目标 entry**。故本次改动只在**重建过的 entry（eln_project_list）**里生效；
  其它用到 `shared/datatable` 的页面要等**下一次正式 `assets:precompile`（全量构建）**才一并受益 ——
  代码是宿主级正确，落地按构建粒度分批。**不影响**本次验收（ELN 列表页已重建）。
- **遗留**：`saveTableState` 里 `colId === 'checkbox'` 的「钉左」判断对 AG Grid v32 实为**死代码**
  （真实 id 是 `ag-Grid-ControlsColumn`）—— 属既有行为，不在本 ADR 扩面，另行记录。

### B（未实施）

- 待裁决，无代码后果。

## B 部分：三条候选路线（请裁决）

| 路线 | 做法 | 代价 / 风险 |
|---|---|---|
| **① 行级补齐（推荐，最小切口）** | 「访问权限」行菜单项**已就位**（落 `/access_permissions/projects/:id`）。若要补 **可见性矩阵**，在 `ElnRowMenuRenderer` 增一项「权限矩阵」→ 行 payload 增 `actions.visibility_matrix`（后端 `access_permissions_project_visibility_matrix_path`），仅 `can_manage_project_users?` 时 `enabled`。 | 纯行级，非「页面级」；但这是 access_control 在列表页**唯一合理接法**（矩阵需单项目）。改动仅 eln_ui addon。 |
| **② 真·页面级（无原生对应物）** | 列表页**工具栏/页头**加一个「权限设置」按钮。 | **无落点**：两条 access UI 都要 `@project`，列表页无当前项目。强做需「先勾选单个项目 → 才可点」，交互别扭、且违背原生范式。 |
| **③ 仅验证 + 文档** | 确认现有行菜单 `access` 链路可用（已下发、已映射），不新增。 | 零改动；若你的意图正是「确认列表页能进权限设置」，这条即达成。 |

## 验证（A 部分，真机 · 无缓存 headless Chromium + 现签 Warden 会话）

对 `eln_project_list`（已重建 entry，加载 `eln_project_list-0f1a9783…js`）：

| 场景 | 注入 | 断言 | 结果 |
|---|---|---|---|
| 列结构变化 | stale 状态（`columnsState` 缺 `favorite`、无 `colSig`） | 旧状态作废 ⇒ favorite 列出现 | `starIcons=5`、表头恢复，`0 pageerror` ✅ |
| 有效定制保留 | 完整列 + 正确 `colSig` + `description` 隐藏 | 状态**保留** ⇒ 描述列保持隐藏 | 表头**无「描述」**、`starIcons=5`、`0 pageerror` ✅ |
| 重存带签名 | 上述加载后查 DB | `colSig` 已写入且含 `favorite` | `colSig="archivedOn|…|favorite|…|updatedAt"` ✅ |

## 关联

- ADR-0035（AG Grid 栈选型）｜ADR-0037/0038/0039（eln_ui 项目列表 V1 补缺批次一~三）
- 代码真源：`app/javascript/vue/shared/datatable/table.vue`（colSig 自愈合）
  ｜`addons/eln_ui/app/services/scinote/eln_ui/project_list_payload.rb`（行 `actions.access`）
  ｜`app/views/experiments/index/_header.html.erb`（visibility_matrix 入口）
  ｜`config/routes.rb:394-409`（visibility_matrix 路由）
