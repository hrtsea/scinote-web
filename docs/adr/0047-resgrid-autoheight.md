# 0047 — ResGrid 自适应高度（按当前页行数撑开，无内部滚动条）

- 状态：已落地并真机验证（2026-10-12）
- 上游：ADR-0022（addon 路由零入侵 / addon↔host 边界）、ADR-0045（workbench 并入 eln_ui）、ADR-0046（helper 转发修复）
- 关联代码：`addons/eln_ui/app/javascript/vue/eln/views/ResGrid.vue`、同目录 `ProjectDetail.vue` / `ResCenter.vue`
  、宿主 `app/javascript/vue/shared/datatable/table.vue`

## 背景 / 问题

`eln_ui` 内嵌 **12 张 AG Grid 表**都经 `ResGrid.vue` 薄封装，底层复用**宿主** `app/javascript/vue/shared/datatable/table.vue`
（AG Grid v32.3.9，与 `/projects` 同引擎）。旧写法由调用方给固定高度（`height="240px"` / `300px` / `320px` / `360px`），
经 `ResGrid` 的 `.rc-grid-host` 固定高度 + 宿主网格 `h-full` 撑满 ⇒ **内容少于高度时留白、多于高度时表格内部出现独立纵向滚动条**。

用户诉求（截图反馈）：**表格按显示的条目数自动扩展，不要出现右侧表格内的单独滚动条**。

## 约束演变（重要）

1. **初始约束「不能改 host」**：本 fork 铁律（addon↔host 边界，见 ADR-0022）要求 fix 落在 addon 内。
   曾据此实现纯 addon 方案：`ResGrid` 监听 `@table-reloaded` 拿行数，按 `行数×40 + 表头40 + 缓冲` 手算容器高度。
   **真机验证失败**：AG Grid 内部高度分解与手算不匹配，`.ag-body-viewport` 只有 49px（内容 120px）、
   仍出现 16px 内部滚动条 —— 手算式撑不满网格。
2. **用户随后明确放宽**：*"为了简化代码还是采用宿主 table.vue 高度自适应吧，便于在其他设备比如移动设备上面查看"*。
   遂改用宿主 `domLayout:'autoHeight'`（AG Grid 官方机制），代码大幅简化、且原生支持行高不固定与移动端。

**最终约束**：可以改 host，但必须是**向后兼容的可选 prop（默认关）**，原生 `/projects` 等全站表格零影响。

## 决策

**宿主提供 opt-in `autoHeight` 开关，`ResGrid` 默认透传开启**：

1. **宿主** `shared/datatable/table.vue`：
   - 新增 prop `autoHeight: { type: Boolean, default: false }`；
   - `gridOptions` 增加 `domLayout: this.autoHeight ? 'autoHeight' : 'normal'`；
   - `<ag-grid-vue>` 的 `flex-grow h-full` 改为条件类（autoHeight 时**不施加固定高度**，让 AG Grid 自行撑开到当前页行数）。
2. **`ResGrid.vue`**：`<DataTable ... :auto-height="!height" />` —— 不传 `height` ⇒ autoHeight；传 `height` ⇒ 固定高度 + 内部滚动
   （保留作个别长表的 override 旋钮，Q4=B）。删掉初版全部手算高度逻辑（`rowCount` / `effectiveHeight` / `BUFFER`）。
3. **移除全部 9 处调用方显式 `height`**（ProjectDetail 7 + ResCenter 2 处 `:height="'360px'"`），统一走默认自适应。
4. **保留服务端分页**（`scrollMode='pages'`）—— 高度=当前页行数，超一页靠底部翻页，滚动条转移到外层页面（Q2=A 既定取舍）。

## 关键事实（代码核对，非推测）

- AG Grid `domLayout:'autoHeight'` 语义：网格自身测量内容、按"表头 + 当前页行数"撑开，**不读父容器高度**。
  这与宿主"自研分页条 + `scrollMode='pages'`（非 AG Grid 内置 pagination）"兼容（autoHeight 的已知限制正是不能配 AG Grid 内置分页，此处不适用）。
- 宿主旧高度链：`div.w-full.h-full`（line 40）→ `ag-grid-vue.ag-theme-alpine.w-full.flex-grow.h-full`（line 50）。
  autoHeight 下仅去掉后者的 `flex-grow h-full`，外层 `h-full` 不影响（autoHeight 不读父高）。
- 12 张表分布：`ProjectDetail.vue` 7 张（experiments/metrics/taskCloseReview/requiredDocs/otherDocs/members/cost）
  + `ResCenter.vue` 5 张（ledger/consume/apply/by_project/by_member）。本次移除全部 9 处显式 `height`。
- `ResCenter` 卡片表原本就**想要**自适应高度（`ResGrid.vue` 旧注释："资源中心卡片是自适应高度，不能靠 flex 撑开"），
  固定高度只是给 AG Grid 的妥协，本决策消除该妥协，非回归。

## 真机验证（prod 容器 :3000，真实 Warden 会话，Edge）

| 页面 | 表 | 行数 | host_clientH / scrollH | agBodyViewport | 滚动条元素 |
|---|---|---|---|---|---|
| `/projects/34/eln_project_detail` | 项目指标 | 3 | 283 / 283 | 150 / 150，`overflowY:hidden` | 不存在(w=0) |
| 同上 | 任务关闭审核 | 8 | 453 / 453 | 320 / 320 | 不存在(w=0) |
| `/eln_res_center` | rc_ledger / rc_consume / rc_apply | 8 / 11 / 11 | 各自相等 | 各自相等 | 不存在 |
| 同上 | rc_by_project / rc_by_member | 3 / 2 | 283 / 283 | 150 / 150 | 不存在 |
| `/projects/34/...`（Pixel 5 375px） | 项目指标 | 3 | 299 / 299 | 150 / 150 | 不存在，且无横向溢出 |

**5/5 ResCenter 表 + ProjectDetail 全表 `host_internalScroll=false`、滚动条元素宽度 0、`overflowY:hidden`。**

## 后果

- ✅ 12 张表全部按当前页行数自适应；表格内部独立纵向滚动条消失（滚动转移到外层页面）。
- ✅ **移动端友好**（用户动机）：AG Grid 原生 autoHeight 不依赖固定行高假设，375px 视口同样无内部滚动。
- ✅ 宿主改动**opt-in 且默认关**（`autoHeight: false`）⇒ `/projects` 等全站表格行为不变。
- ✅ 消除了初版"固定 40px 行"假设的脆弱性（换行表 / 行高变化由 AG Grid 自行处理）。
- ✅ 分页/排序/筛选等行为不变（`scrollMode='pages'` 服务端收口）。
- ⚠ 每页若选 `100` 档，表高 ≈ 100×40 ≈ 4.2m —— 属 Q2=A（无上限、滚动转移到页面）的既定取舍，非缺陷。
- ⚠ 宿主 `table.vue` 从此多一个 prop；若 upstream 有合并冲突，冲突点集中在 3 处小改动（prop / domLayout / 条件类）。

## 关联

- 0022（addon↔host 边界）—— 最终版本经用户明确授权破例改 host，但以"opt-in 默认关"保持零影响面。
- 0045 / 0046 —— 同批 ELN 内嵌网格收口工作的延续。
