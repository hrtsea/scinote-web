# ADR-0039: 项目列表（eln_ui）V1 全功能补缺批次三 —— 文件夹层级面包屑

> spec `SCN-PROJ-LIST-7` 第 4 条：「进入文件夹层级 + 提供返回上一层的入口」
> 接续 ADR-0035（AG Grid 栈选型，不可推翻）+ ADR-0037（批次一）+ ADR-0038（批次二）

## Status

Accepted（后端补 `rootUrl` + 前端渲染，已真机验收）

## Context

ADR-0037 的「未做（留待后续批次）」清单里，**「文件夹层级面包屑 + 返回上一层（SCN-7）」是唯一带
spec 硬性验收条款却仍未落地的一项**（其余如页头工作台入口 / 筛选面板 / 评论描述就地可点，或非硬条款、
或需引 TinyMCE 另立）。

实证（均对 HEAD / 运行态）：

- **V1 原型已实现**：`ELN系统-Vue3/src/views/ProjectList.vue:159-182` 有 `<nav class="folder-crumbs">`
  （`全部项目 / <trail>` + 「返回上一层」），V1.32 票 #84 真机验收记录「进 PF4 面包屑『全部项目 / 000』
  +『返回上一层』」。
- **后端早已装配、前端却丢**：生产 `addons/eln_ui` 侧，
  - `ProjectListRows#build_trail`（`project_list_rows.rb:162-175`）从当前文件夹逐级 `parent_folder`
    回溯，返回**根 → 当前**（含当前）的有序数组，带 `MAX_TRAIL_DEPTH=20` 防环；
  - `ProjectListController#payload` 传 `current_folder:` / `folder_trail: row_set.trail` /
    `folder_url_base: page_self_path`（`project_list_controller.rb:373-375`）；
  - `ProjectListPayload#folder_nav_block`（`project_list_payload.rb:538-556`）产出
    `folderNav: { current, trail:[{id,name,code,url}], upUrl }`，并在顶层返回全空块。
- 🔴 **两个前端缺口**：
  1. `list.vue` **完全不渲染**面包屑（模板只有 `<DataTable>` + 模态框）；
  2. `created()` 里 `axios.get('/eln_project_list.json')` **不带当前 query** ⇒ controller 的
     `current_folder`（按 `params[:project_folder_id]` 定位）恒为 nil ⇒ `folderNav` 恒空。
     **静默失败**：无报错、无日志，面包屑永远不出现，最难查的一类。

## Decision

原则：**后端只在既有 `folderNav` 上补一个字段；前端只做「渲染 + 带上 query」；不新增端点、不新增路由、
不重造 URL**。

### 1. 后端：`folderNav` 补 `rootUrl`（唯一真源）

`folder_nav_block` 增加 `rootUrl: @folder_url_base`（顶层 / 嵌套恒有）。

**为什么必须补**：`upUrl` 在嵌套时指向**父级**、只在顶层文件夹时才等于根 —— 单靠 `upUrl` 拼不出
「全部项目」的落点，而面包屑**每一级**（尤其中间级）都必须能回到顶层。若不补，前端就得自己
`location.pathname` 去 query 拼根路由，违反本页铁律「**前端不拼任何路由**（路径词汇表只一套，
路由改名只改后端）」。补此一字段，前端所有 `href` 都原样取自 payload。

### 2. 前端 `list.vue`：渲染面包屑（顶层不渲染）+ 修 ui 拉取丢 query

- **修 query**：`axios.get(\`/eln_project_list.json${window.location.search}\`)` —— 让
  `project_folder_id` / `view_mode` / `filters` 一并带到 index，后端才能定位 `current_folder`。
- **模板**：外层包 `.eln-project-list-root`（flex column），内层 `.eln-project-list-body` 包
  `<DataTable>`；面包屑 `<nav class="eln-folder-crumbs">` 置于其上层。
  - `v-if="folderCrumbs.length"` —— **trail 为空（顶层）即整块不渲染**，显式留白，
    不渲染「点了回原地」的死入口（与 V1 原型同款判断）。
  - 结构：`<a rootUrl>全部项目</a>` + `trail` 逐级（`/` 分隔）+ 末级 `.efc-current`（加粗、
    中性色、`pointer-events:none` **不可点击**，守 spec「末级不可点击」）+ `.efc-spacer` +
    `<a upUrl>返回上一层</a>`。
  - `href` **全部**来自 payload（`folderNav.rootUrl` / `trail[].url` / `upUrl`），前端零拼接。
- **computed**：`folderNav` / `folderCrumbs` / `folderRootUrl` / `folderUpUrl`（纯读 `ui.folderNav`）。

### 3. 样式 + 高度链（scoped，只补本页）

`styles/eln_project_list.scss` 增：

- `.eln-project-list-root { display:flex; flex-direction:column; height:100%; }`
- `.eln-project-list-body { flex:1 1 auto; min-height:0; }`
- `.eln-folder-crumbs`（分隔符 `/`、链接用 `--sn-science-blue`、末级中性加粗）。

**高度链是硬约束**：挂载点 `#eln-project-list` 带宿主 `.fixed-content-body`（定高
`calc(100vh − content-header-size − navbar-height)`，见 `shared/content_pane.scss:17`）。面包屑占据
自然高度后，必须让 DataTable 落进「剩余高度」—— 否则 AG Grid 以 0 高度渲染（在 DOM 里存在但视觉空白）。
`.eln-project-list-root` 撑满定高 + `.eln-project-list-body` 吃剩余 ⇔ DataTable 的 `h-full` 才有确定父高。
面包屑不渲染时 body 独自撑满，行为与改造前**逐像素一致**。

## Consequences

- **得**：补齐 spec SCN-7 硬条款；面包屑每一级可回溯（含嵌套多级）；「返回上一层」与原生
  `project_folder_id` 语义一致；所有 URL 单一真源（后端 `page_self_path`），路由改名两侧不脱钩。
- **得（顺带修 bug）**：`created()` 的 query 丢失被一并修掉 —— 这同时修好了此前**任何**依赖
  index payload 里「随当前层级变化」的字段（面包屑之外，`view_mode` 等也受影响）。
- **舍**：DataTable 外层多一层包裹 + 高度链由 CSS 显式承担（换来面包屑与表格共存的确定布局）。
  面包屑与表格 toolbar 的**上下次序**与 V1 原型略有差异（V1 是 `[toolbar][面包屑][表格]`，
  本页 toolbar 在 DataTable 内部 ⇒ 呈 `[面包屑][toolbar][表格]`）—— 可接受，
  SCN-7 只要求「进入层级 + 有返回入口」，未约束相对次序。
- **已知遗留（不在本 ADR）**：
  - 分隔符 `/` vs `>`：spec「待确认 H」/ `OPEN-2` 仍未裁决，本页沿原型现状用 `/`（不擅自改全站）。
  - 筛选面板 / 页头工作台入口 / 评论与描述就地可点（SCN-11/12，需引 TinyMCE）—— 仍留待后续批次
    （见 ADR-0037「未做」清单）。
  - 宿主 DataTable 列状态迁移（ADR-0038-D 遗留）—— 共享组件改动，单独立项。

## 验证（真机，无缓存 headless Chromium + 现签 Warden 会话）

| 场景 | 断言 | 结果 |
|---|---|---|
| 顶层 `/eln_project_list` | 面包屑**缺席**；表格撑满 | `crumbPresent=false`；mount/root/body 均 772px，grid 620px |
| 文件夹内 `?project_folder_id=4` | 面包屑出现且链接正确 | `crumbText="全部项目 / 000 返回上一层"`；`全部项目→/eln_project_list`、`000→/eln_project_list?project_folder_id=4`（`efc-current`）、`返回上一层→/eln_project_list` |
| 高度链 | 面包屑占 39px、表格吃剩余、不溢出不塌 | body 772→733px（−39），grid 620→581px（−39） |
| 控制台 | 无 JS 报错 | `pageerror` 空 |

## 关联

- ADR-0035（AG Grid 栈选型）｜ADR-0037（批次一判据硬伤）｜ADR-0038（批次二收藏/文件夹视觉/批量/主题）
- spec：`规格/eln-system/spec.md`（SCN-PROJ-LIST-7；V1.32 变更摘要 / 待确认 H 面包屑分隔符）
- 代码真源：`addons/eln_ui/app/javascript/vue/eln_project_list/{list.vue,styles/eln_project_list.scss}`
  ｜`addons/eln_ui/app/services/scinote/eln_ui/{project_list_payload.rb,project_list_rows.rb}`
  ｜`addons/eln_ui/app/controllers/scinote/eln_ui/project_list_controller.rb`
