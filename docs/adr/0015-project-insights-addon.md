# 0015 — Project Insights（科学项目管理仪表盘）以 addon 形式实现

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-008（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（经 `/grill` 逼问确认）

## Context

官网「Scientific Project Management / Project Insights」页四大 Widget（状态饼图 / 团队负载堆叠柱图 / 瓶颈检测 7·14·30+ 天 / 截止日期跟踪）；代码库现状为全仓 0 业务级 `insights` 代码（仅 vendor CSS 一处命中）。但约 70% 基础已具备：`DEFAULT_DASHBOARD_CONFIGURATION`（Array）、`MyModule` 谓词、`echarts` option 配置、`current_tasks` 过滤链。

## Decision

- 以独立 Rails Engine `addons/project_insights/`（`Scinote::ProjectInsights::Engine`，`isolate_namespace`）承载全部逻辑；**绝不修改核心 `app/`**。
- **Widget 注册（数组追加，非 merge!）**：`DEFAULT_DASHBOARD_CONFIGURATION` 是 Array，addon 在自身 `initializer` 中以 `Extends::DEFAULT_DASHBOARD_CONFIGURATION.concat([...])` / `<<` 追加 4 个 widget 配置项，**禁止改 `extends.rb` 本体**、不预置 `position`。
- **灰度门控（AddonSetting 契约，opt-out）**：widget 仅在 `Scinote::ProjectInsights.enabled?`（读 `AddonSetting.enabled?('project_insights')`）为真时注册。初版 ENV 方案已**被 0020 取代**——改用 `AddonSetting` 表做实例级开关 + 参数（`default_period_days`），不再依赖 ENV。关闭即不注册、零渲染零查询。
- **权限（复用，不加新权限）**：dashboard 本身已登录门控；本 addon **不新增** `can_view_project_insights?`。
- **聚合服务** `Scinote::ProjectInsights::AggregatorService`：复用 `MyModule.active.readable_by_user(current_user, current_team).joins(experiment: :project)...`；状态流动态查 `MyModuleStatusFlow`（团队流 + global 流）。
- **图表（复用 echarts option，新建 addon pack）**：复制 `charts.js` 的饼图 / 堆叠柱图 `option` 形状到 addon 自有 pack `insights_charts.js`，不改核心 `charts.js`。
- **下钻（复用 current_tasks 过滤）**：各 widget 链接到 `dashboard_current_tasks_path`（带预设过滤参数），不新建任务列表页。

## Consequences / 风险

- 与上游冲突风险点（rebase 时逐项核对）：`extends.rb` 的 `DEFAULT_DASHBOARD_CONFIGURATION` 数组、`left_menu_bar_helper` decorator、`current_tasks_controller` decorator、`config/routes.rb` 的 mount、`config/locales` 的 `dashboard.insights.*` 等键、图表 pack 与 `[data-insights-chart]` 钩子。
- 状态流可定制；大团队聚合须对 `updated_at`/`due_date`/`my_module_status_id` 建覆盖索引或缓存；截止日期按 **UTC**（`Time.current.utc`）。
- 瓶颈检测排除 `completed?` 任务；截止分桶现算（无 `approaching_due_dates` 作用域）。

## 关联

- 0020（addon 配置自声明 / 设置页 addon 化）
- 0012（异步导出）
- `docs/开发计划/官方功能/Project Insights/实现现状与开发计划.md`（PRD / Issues P1–P9）
- `docs/development/addon-dev-workflow.md`
