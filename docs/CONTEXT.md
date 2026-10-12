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

## 个人行动工作台（eln_workbench）
`/eln_workbench` 是「每天从这里开始」的个人行动页（ADR-0048）：**只显示需要处理的事**，
纵排三区 —— 待办事项（我的未完成任务 + 我的申请待验货）/ 审批事项（待我审：资源申请初审终审、
任务关闭、到货验收，按名单真源判定）/ 进行中的项目（参与 ∩ 活动，与项目列表页同一真源）。
统计块（KPI 卡/状态分布/小组汇总）已删——工作台不复述别处已有的数字。「你能看到」的边界 =
当前 team 内可读（`readable_by_user ∩ current_team`）。与「统计仪表盘」相对：后者回答"有多少"，
前者回答"我现在该做什么"。

## 待我审（审批可见性口径）
「某条审批该不该出现在我的工作台」不由工作台自己推断，一律问名单真源：
`ResourceApprovalPolicy`（资源申请/到货验收，`ProjectApprover` 显式名单，fail-closed）与
`TaskCloseWorkflow.reviewable_project_ids`（任务关闭，Project 级 Owner UA）。工作台列出的每条
都必须点进去能动——列出去做不了的单就是口径破裂。

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

## 必传文档固定清单（ADR-0049）
项目结题归档前必须齐备的 5 类文档（**立项申请材料 / 项目任务书 / 年度计划 / 年度报告 /
结题报告**）。用户已撤回「负责人可增删」需求 ⇒ **固定清单**。清单定义住服务端
（`RequiredDocSeeder::REQUIRED_DOC_NAMES`，定序即 position），**展示真源永远是 DB 行**
（`eln_ui_project_documents`，category='required'）——页面渲染的行、计数的分子分母、
上传的目标行，三处同源。与「可配置清单」相对：宿主无可复用的文档分类模型，自建字典表
是纯新增复杂度。

## RequiredDocSeeder（补种器）
必传文档 5 类是固定清单，但台账行是**数据**不会凭空出现 ⇒ `RequiredDocSeeder.seed!(project)`
把 canonical 5 类幂等补种进 `eln_ui_project_documents`（find_or_initialize + position 归一，
非规范名旧行不碰）。**闸门 = 已纳管**：无 `ProjectProfile` 行的项目不补种（文档面板维持空态，
不拿固定清单顶）。挂 `ProjectDetailController#show`（读路径，幂等）而非 payload
（export/测试共用的纯读装配器）或项目创建钩子（「纳管」是事后状态，无创建事件可挂）。

## 已纳管（managed）
项目已进入 ELN 二开台账的状态，判据 = `eln_ui_project_profiles` 有行。由
`ProjectDetailController#update / update_status` 的 `ProjectProfile.upsert_for!` 事后建立，
**不是**项目创建钩子 ⇒ 懒补种只能挂读路径。与「未纳管」相对：后者从没进过 ELN 项目台账，
必传文档面板为空态。

## 其他文档（other 类台账行）
`eln_ui_project_documents` 中 category='other' 的行 = **累积型**过程记录（「过程记录、参考资料等，
随时上传归档」）。与必传 5 类（预置规范行、覆盖式上传）不同构：上传入口在 subhead「上传文档」
按钮（空表时行内入口无处可点），每次上传**创建新行**（name=文件名原样、doc_type=扩展名
downcase、uploader/uploaded_on 自动填）；**不提供替换、不提供删除**——「某日交了什么」的过程
痕迹比「最新版」更重要，传错再传一条。

## 预览/下载端点（附件读取链路）
项目文档行的附件读取走**显式端点** `GET .../eln_project_detail/documents/:id/preview|download`：
controller 校验项目读权限后 `redirect_to rails_blob_path(file, disposition: 'inline'|'attachment')`。
payload 每行下发 `previewUrl/downloadUrl`（仅 file.attached? 时）——**绝不下发 signed_id 直链**
（rails_blob_path 的 signed_id 是永久下载凭证，外溢即失控）。宿主 `CheckBlobPermissions`
给 ActiveStorage RedirectController 挂了第二道权限关（record_type 白名单，已加
Scinote::ElnUi::ProjectDocument 分支）⇒ signed_id 即使外溢也会被再查一次。
