# Project Insights Addon — 功能规格（SPEC）

> 事实基准：`frame_014.png`（独立 `/insights` 页面截图，599×302）+ **关键区域 4× 放大复核（2026-09-04）** + addon 代码现状（P1–P9 骨架已落地）。
> 本文件为产品/功能级规格，是 `spec/` 下 rspec 的上层契约。与官方 UI 的偏差标注 ⚠️（含是否已落地）。
>
> ⚠️ **2026-09-04 二次校准（推翻 2026-09-03 的两处结论）**：
> 1. Tasks due 的 5 档是 **`Overdue / Today / Tomorrow / This week / Next week`**（**Overdue 独立成档**，且**无 `More weeks`**），不是此前记载的 `Today/.../More weeks`。
> 2. Team workload 右上角是成员多选下拉 **`14 options selected`**，不是副标题 `N subjects covered`。
> 3. Bottlenecks 的 `No activity for:` 是**分段选择器标签**（`30 days | 14 days | 7 days`），选中档下方展示任务列表；空状态天数**随选中档变化**（截图为 14 days），非固定 7 天。

## 0. 呈现形态

- 独立页面：`GET /insights`（`insights#index`，`project_id` 可选）→ 2×2 网格 + 项目选择器（frame_014 即此形态）。
  - 布局：左上 **Status Overview**（large）、右上 **Team workload**（large）、左下 **Bottlenecks**（medium）、右下 **Tasks due**（medium）。
- Dashboard widget：❌ **不实现**。本 addon 以**独立 `/insights` 页面**交付（既定设计，非偏差）。原计划 P1 的 `Extends` 数组追加挂件注册已废弃（`registration_spec.rb` 注释「dashboard widget 注册已撤销，改为独立 /insights 页面」正是该决策记录）。

## 1. Status Overview（W1）

- 标题：`Status Overview`（i18n 已对齐短标题）。
- 环形（donut）饼图，颜色取 `MyModuleStatus#color`。
- **中心显示任务总数**：上方数字、下方标签 `Tasks`（frame_014 = **73**）。
  - ✅ 已落地：JS `buildPieOption` 对 `count` 求和后写入 `title.text`，标签走 i18n `data-total-label`。
- **右侧图例榜**：名称 + 计数（frame_014：Not started 48 / In progress 4 / Completed 3 / In review 15 / Done 5）。
  - ✅ 已落地（2026-09-04 P11）：`buildPieOption` 启用 echarts `legend`（vertical，右侧），`formatter` 渲染「名称 + 计数」，对齐官方图例榜。
- 数据：`GET /insights?kind=status` → `[{ id, name, color, count }]`（含 count=0 状态）。
- 下钻：扇区 → `current_tasks`（`statuses[]`）。

## 2. Team workload（W2）

- 标题：`Team workload`（i18n 已对齐短标题）。
- **右上角成员筛选下拉 `N options selected`**（frame_014 = **14 options selected**）。
  - ✅ 已落地（2026-09-04 P12）：不仅渲染计数（JS 按 distinct 用户数填充 `data-user-count-template`），且 widget 内渲染成员多选 toggle（`[data-member-filter]`，JS 依负载数据动态填充）；取消勾选即经 `GET /insights?kind=workload&member_ids[]=...` 按所选成员**重绘柱图** + 实时更新计数列。空结果时 ActiveModelSerializers 会把 `[]` 包裹为 `{"data":[]}`，已在 `insights_charts.js` 的 `normalizeInsightsData` 归一化（仅解包 `{ data: [...] }`，保留计数 Hash）。
- 堆叠柱图：X = 成员名，Y = `Number of Tasks`，按状态堆叠。
- 数据：`GET /insights?kind=workload` → `[{ user_id, user_name, status_id, status_name, status_color, count }]`。
- 下钻：柱 → `current_tasks`（`assigned_user_id` + `statuses[]`）。

## 3. Bottlenecks（W3）

- 标题：`Bottlenecks`（i18n 已对齐短标题）。
- 官方形态：标签 **`No activity for:`** + 分段选择器 **`30 days | 14 days | 7 days`**（frame_014 选中 `14 days`），选中档下方列出该档任务。
- 空状态：绿色对勾图标 + **`Well done.`** + **`All tasks had some activity within the last {N} days.`**，其中 N = 当前选中档天数（截图选中 14 days → 14）。
- 本实现形态（⚠️ 与官方不同）：三张**并行区间卡片**，非阈值分段器——
  - `7-14 days` / `14-{period} days` / `{period}+ days`（`period` = `default_period_days`，设置页默认 90，配置可改）；
  - ✅ 已补：`No activity for:` 标签（`no_activity_for`）；
  - ✅ 已补：空状态容器（`data-empty-state`），三档计数**全为 0** 时由 JS 显示，文案取最小档阈值 7 天（该情形下语义成立：无任务超过 7 天未活动）；
  - ✅ 已落地（2026-09-04 P10）：**分段选择器交互近似**——点击某档卡片即在 widget 内联渲染该档任务列表（`GET /insights/tasks?kind=bottlenecks&bucket=seven|fourteen|thirty_plus`，端点按 `bottleneck_bucket` 谓词返回，与计数同边界），列表底部保留「在任务列表中查看全部」下钻链接。
- 数据：`GET /insights?kind=bottlenecks` → `{ seven, fourteen, thirty_plus }`（已排除 `completed?`）。
- 下钻：卡片 → `current_tasks`（`stale_bucket`）。

## 4. Tasks due（W4）

- 标题：`Tasks due`（i18n 已对齐短标题）。
- ✅ **档位已对齐官方 UI**：**5 档** `Overdue / Today / Tomorrow / This week / Next week`（frame_014 顺序即此）。
  - `overdue`：`due_date.to_date < Date.current`
  - `today`：`== Date.current`
  - `tomorrow`：`== Date.current + 1`
  - `this_week`：`> tomorrow` 且 `<= Date.current.end_of_week`（周起始随 Rails 配置，默认周一）
  - `next_week`：**兜底档**，`> end_of_week`（官方 5 个 tab 中无 `More weeks`，更晚截止归入此档）
- 数据契约：`GET /insights?kind=due_dates` → `{ overdue, today, tomorrow, this_week, next_week }`。
- 官方形态：选中 tab 下方**列出具体任务**（任务名 + 状态色点/状态名 + 红色逾期/到期时间 + 成员头像，可滚动）。
  - ✅ 已落地（2026-09-04 P10）：五档卡片点击即在 widget 内联渲染该档任务列表（`GET /insights/tasks?kind=due_dates&bucket=overdue|today|tomorrow|this_week|next_week`，端点按 `due_date_bucket` 谓词返回，与计数同边界），列表底部保留「在任务列表中查看全部」下钻链接；官方 tab 形态以并行卡片 + 内联列表近似。
- 下钻：卡片 → `current_tasks`（`due_bucket`）。

## 5. 数据端点（InsightsController#index）

- `GET /insights?kind=status|workload|bottlenecks|due_dates` → JSON。
- `GET /insights`（无 kind）→ 独立页面 HTML（`@project`, `@projects`）。
- 受 `enabled?` 与 `current_team` 保护（无 team → 403）；`project_id` 须属当前 team（越界 → 404）。
- 未知 `kind` → 400。

## 6. 权限与灰度

- `enabled?` 读 `AddonSetting('project_insights').enabled`（默认 true）。
- 复用 dashboard 登录门控，无新权限文件。

## 7. 与官方 UI 偏差校准清单（frame_014）

| # | 偏差 | 状态 |
|---|---|---|
| **A** | Tasks due 档位 = `Overdue/Today/Tomorrow/This week/Next week`（Overdue 独立，无 More weeks） | ✅ 已落地（聚合 + partial + i18n + spec，2026-09-04） |
| **B** | Bottlenecks：`No activity for:` 标签 + 全零空状态文案 + 分段选择器交互（点击档 → 该档任务列表） | ✅ 已落地（2026-09-04 P10：三档卡片点击内联渲染该档任务列表） |
| **C** | Status 环形图中心总数（`Tasks` + N） | ✅ 已落地（JS 求和） |
| **D** | Workload 成员筛选计数 `N options selected` | ✅ 已落地（2026-09-04 P12：成员多选 toggle 过滤柱图 + 计数列实时更新；空结果 AMS 包裹 `{"data":[]}` 已在 `insights_charts.js` 归一化） |
| **E** | 短标题对齐（`Status Overview / Team workload / Bottlenecks / Tasks due`） | ✅ 已落地（en + zh-CN） |
| **F** | Status 右侧**图例榜**（名称 + 计数） | ✅ 已落地（2026-09-04 P11：饼图 `legend` 渲染名称 + 计数） |
| **G** | Bottlenecks / Tasks due **档内任务列表**（官方为 tab + 列表，非计数卡片） | ✅ 已落地（2026-09-04 P10：内联任务列表，`/insights/tasks` 按档端点） |
| **H** | 试用到期提示（"Your insights trial expires in 12 days"）与 "Go to project" 链接 | 非核心，由 license/营销层控制，**不实现** |
