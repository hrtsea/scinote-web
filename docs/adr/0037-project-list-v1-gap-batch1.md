# ADR-0037: eln_project_list 以 V1/spec 为功能基准、留在 AG Grid 栈补缺

## Status
Accepted

## Context
用户要求「根据 V1 版本（`F:\eln开发\ELN系统-Vue3`）恢复 eln_project_list 缺失功能，并对照 spec/PRD」。
查证后发现：

- V1 原型仓 `src/views/ProjectList.vue` 是 **1930 行手写 flex 表格**，带 `pinned[]` 钉列、
  `useColumnResize`、分页条、卡片视图等。
- spec `规格/ELN系统/spec.md`（SCN-PROJ-LIST-7~13）与 PRD（V1.31）对分页档位、操作列列名、
  评论/描述就地可点、文件夹面包屑有硬性验收条款。
- **🔴 与 ADR-0035 冲突**：ADR-0035 的 V2.0 修订已由用户拍板「线上真源 = 引用原生 AG Grid 栈」，
  并明写「原型仓 V1 的 `pinned[]` 实现**非线上真源**」。

进一步实证推翻了「需要搬 V1 手写表格」的假设：
- 宿主 `shared/datatable/table.vue` **原生自带分页**（`scrollMode` 默认 `'pages'`、`perPage`/`page`、
  读 `meta.total_pages`）与**卡片视图**（`#card` 插槽 + `viewRenders`）。
- addon 控制器**已按 V1.31 实现分页**（`normalize_per_page`：0=全部 / 非法回落 20 / 越界返空数组不 500；
  payload 下发 `pagination.{totalPages,totalEntries,perPageOptions}`）。

⇒ 留在 AG Grid 栈即可满足 spec，无需移植 1930 行手写表格。

## Decision
1. **口径**：以 V1 为**功能基准**、**留在当前 AG Grid 栈**（与 ADR-0035 一致，不推翻）。
2. **首批范围（「判据硬伤」四项）**，全部基于 AG Grid 栈做最小改动：
   - **每页档位对齐 spec `[0,20,50,100]`**：宿主 `table.vue` 新增可选 prop
     `perPageOptionsOverride`（默认 null ⇒ 原生 `[10,20,50,100]` 不变），addon 从服务端
     `pagination.perPageOptions` 注入真源；0 渲染为「全部」（不依赖 i18n 键，传 `[0,'全部']` 对）。
   - **操作列列名「操作」**（SCN-PROJ-LIST-10，V1.30 裁定）：`columnDefs` 里 `rowMenu` 列
     `headerName:'操作'`，**有意偏离原生空表头**，列管理面板可读名同此。
   - **卡片视图**：去 `table-only`，传 `:view-renders="[{type:'table'},{type:'cards'}]"`；
     手绘 ELN 专属 `renderers/project_card.vue`（读 ELN 行形状 `detailUrl`/`createdAt`/`members`，
     **不复用宿主 `host/projects/card.vue`**——它读原生 `urls.show` 会 `TypeError` 空白卡）。
   - **状态口径单一真源**：抽 `renderers/status_map.js`，表格 `status_renderer.vue` 与卡片共用。

## Consequences
- 容易：spec 硬条款分页档位/操作列名/卡片视图补齐；原生 `/projects` 页因 `perPageOptionsOverride`
  默认 null **零行为变化**（向后兼容）。
- 容易：单一真源——状态映射、卡片行形状各一处，不与表格列渲染器分叉。
- 困难/代价：
  - 卡片视图需自维护一份 ELN 卡面（不复用宿主卡），长期多一份渲染代码；换取「不把原生行形状
    强加进 ELN grid payload」的边界清晰。
  - `datatable` JS 翻译包为预生成产物且 `config/i18n-js.yml` 缺失，**不可重编**——本轮为此放弃
    在 yml 加 `datatable.all` 键，改用 `[值,标签]` 对传档位标签（见坑 2）。
  - 视图状态持久化（`skip-save-table-state=false`）使测试默认可能落在卡片视图，harness 需显式切回表格。
- 未做（留待后续批次，依同口径）：文件夹层级面包屑+返回上一层（SCN-7）、页头工作台入口、
  筛选面板、收藏列（需后端 `with_favorites` scope + urls）、评论/描述列就地可点（SCN-11/12，
  需引 TinyMCE）、批量操作条（需传 `actionsUrl`）。
