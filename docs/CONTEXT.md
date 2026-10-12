# CONTEXT — 术语表（Glossary）

> 本文件只收术语定义，不含实现细节与决策记录。决策见 `docs/adr/`。

## ELN UI（eln_ui）
本 fork 的核心功能 addon，承载 ELN 的 Vue3 前端（app/javascript/vue/eln/）与配套后端
（controllers / services / models / decorators）。是被宿主与多个页面硬依赖的承重件。

## Workbench（工作台）
按当前登录角色渲染的首页仪表盘（REQ-DASHBOARD / SCN-DASH-1~7），聚合通知未读、项目参与、
待审资源申请等实时统计。
**2026-10-12 起已从独立 addon 并入 eln_ui**（见 ADR-0045）：其前端 Vue 应用、URL 字面量、
数据口径原本就位于 eln_ui，并入后不再是独立 addon。

## 单一真源（single source of truth）
某类数据口径只由一处代码/类定义，禁止两处各写一遍。
Workbench 的 KPI / 待办数字必须与 eln_ui 的 `Scinote::ElnUi::ProjectListScope`、
`NotificationsPayload`、`ResourceApplication` 等类同口径——卡片数字必须逐位等于点进去列表页
筛出来的条数。违反此不变式是本项目两次出事的形态。

## 优雅禁用（graceful disable）
addon 的启用/禁用**只由 Gemfile 一行决定**：注释掉 `gem 'scinote_<x>'` ⇒ Bundler 不加载该引擎
⇒ routes initializer 不运行 ⇒ 路由未注册 ⇒ **宿主照常启动**，仅该 addon 的路径 404（而非 500 /
启动崩溃）。这是 addon 零入侵契约的半边保证。

## 并入 / merge
把本是 eln_ui 功能的 workbench 收口进 eln_ui addon：删除独立 addon 目录，将其文件（controller /
payload / view / route / test）迁到 eln_ui 并改命名空间。与「解耦」相对。

## 自适应网格高度（ResGrid autoHeight）
`eln_ui` 内嵌 12 张 AG Grid 表（ProjectDetail 7 + ResCenter 5）经 `ResGrid.vue` 薄封装复用宿主
`shared/datatable/table.vue`。默认**不传 `height`** ⇒ `ResGrid` 透传 `:auto-height="!height"` ⇒ 宿主
`autoHeight` prop 置 AG Grid `domLayout:'autoHeight'`，网格随**当前页行数**自行撑开、
**无内部纵向滚动条**（移动端同样友好，见 ADR-0047）。传 `height` 则回退固定高度（override 旋钮）。
宿主 prop 默认关（`false`）⇒ 原生 `/projects` 等全站表格行为不变。

## addon 零入侵契约（ADR-0022）
宿主 `config/routes.rb` 不得含任何 `to: 'scinote/<addon>/...'` 路由；addon 路由一律由各自
engine 的 initializer 自注册（`app.routes.append { mount Engine => '/' }`）。启用/禁用只由
Gemfile 一行决定。rebase 上游时宿主 `config/routes.rb` 是干净的。

## 跨 addon 硬依赖（本 fork 约束；既有债已消解）
addon 之间通过运行期裸常量引用（如 `Scinote::ElnUi::Xxx`）耦合，而非 gemspec 声明依赖。
停用某 addon 前必须查三路引用：① Ruby 命名空间常量 ② Sprockets `//= require` / engine
`assets.precompile` ③ 路由与 webpack entryList。曾因此导致「禁用 eln_ui 时 workbench 500」
（ADR-0044 §遗留问题，已于 ADR-0045 通过**并入 eln_ui** 消解，仓库无跨 addon 运行期裸耦合残留）。
⚠ 仓库根 `elncp/` 是被 `.gitignore` 排除、**运行期零引用**的迁移前快照副本（见 ADR-0045 §核实），
**非在役控制面板**，不构成宿主耦合，随时可删；勿将其误记为"宿主硬依赖 eln_ui 的既有债"。
