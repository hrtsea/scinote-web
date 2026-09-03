# 架构决策记录 — scinote-web（SciNote 电子实验记录本）

> 由 codebase-memory 知识图谱自动生成。
> 工程标识：C-Users-Administrator-CodeBuddy-20260829210627
> 图谱规模：16,158 个节点 / 46,071 条边（全量索引，8 种语言，0 个文件跳过）。

## 一、系统概览
- **类型**：基于 Ruby on Rails 的**电子实验记录本（ELN, Electronic Lab Notebook）** Web 应用。
- **主要语言**：Ruby（1,676 个文件），前端为 Vue 2/3 单页应用层（372 个 `.vue`），另有 JavaScript（275）、SCSS（147）。
- **可观的配置面**：50 个初始化配置、342 个数据库迁移 —— 属于长期、持续维护的大型项目。

## 二、分层结构（由图谱推导）
- `app` 是主导核心：高 fan-in（344 入 / 51 出）—— 系统的中央枢纽。
- `db`（模型 + 迁移）被 `app` 调用 290 次 —— 典型的以 ActiveRecord 为中心的「胖模型」架构。
- `lib`（fan-in 2 / fan-out 19）作为低层工具/基础设施层（Rack 中间件、i18n、rake 任务、active_storage 扩展）。
- `config` 与 `test`/`spec` 为入口/叶子层，仅有出站调用。
- `Makefile` 具有高 fan-in（15 入）—— 构建/运维编排集中于此。

## 三、关键架构决策（ADR）
### ADR-001：Repository（自定义表）模式是核心领域模型
- 依据：`RepositoryRowService#render` 是全局 fan-in 最高的函数（819 个调用方），且 `repository_*` 聚类是内聚性最强的组之一。
- `Repository`/`RepositoryRow`/`RepositoryColumn`/值类型家族（repository_text_value、repository_list_value、repository_stock_value 等）构成数据模型的骨干。
- 影响：对仓库值渲染/序列化的改动影响面最广 —— 应作为**稳定性关键子系统**对待。

### ADR-002：协议从外部源导入（Protocols.io）
- 依据：`ProtocolImporters::ProtocolsIo::V3::StepComponents#name`（421）、`ExternalProtocolsController#new`（232），以及 `utilities/protocol_importers`、`services/protocol_importers`、`protocol_importers_v2/v3` 目录。
- 系统支持多版本协议导入；需在各导入器版本间保持向后兼容。

### ADR-003：权限模型为「角色 + 用户分配」的集中式设计
- 依据：庞大的 `permissions/` 目录（13 个文件，按领域实体逐一划分）、`PermissionError`/`readable_by_user` 聚类，以及 `user_roles` + `user_assignments` + `team_assignments`。
- 权限按实体显式建模（asset、experiment、project、repository、result、step、team、storage_location、form 等）。
- 影响：新增领域实体必须配套对应的 `permissions/<实体>.rb` 及 user_role 权限集合，否则将处于无防护状态。

### ADR-004：序列化器驱动 API 与导出输出
- 依据：57 个序列化器文件；`Lists::MyModuleSerializer#attributes`（163）是热点函数；重度使用 `active_model_serializers`。
- 模块/仓库的 JSON 形态由序列化器生成 —— 应将序列化逻辑保持在控制器之外。

### ADR-005：导出、通知、提醒使用异步作业
- 依据：26 个 job；`repository_*_zip_export_job`、`team_zip_export_job`、通知/提醒 job，后端为 `delayed_job`。
- 长耗时任务（导出、PDF 预览、提醒）被推入 DelayedJob —— 不应阻塞请求路径。

### ADR-006：AI 协议生成以 addon 形式实现（Create / Import with AI）
- 依据：官网 AI & Automations 页的 Create with AI / Import with AI；代码库现状 `Protocol.ai_parser_enabled?`（`app/models/protocol.rb:293`）已预留「ApplicationSettings 键 `ai_protocol_parser_enabled` + ENV `AI_PROTOCOLS_PARSER`」双重门控，但全仓无任何消费方、无 LLM 客户端。
- 决策：以独立 Rails Engine `addons/ai_protocols/`（`Scinote::AiProtocols::Engine`，`isolate_namespace`）承载全部 AI 协议生成逻辑；**绝不修改核心 `app/`**。
- LLM 接入采用 OpenAI 兼容 Chat Completions + 结构化输出（JSON schema），`AI_PROTOCOLS_PARSER` 即 base URL（兼容 Azure OpenAI）；新增 `AI_PROTOCOLS_API_KEY`、`AI_PROTOCOLS_MODEL`（默认 `gpt-4o-mini`）。`LlmClient` 用策略模式，未来可加 Claude / Ollama 而不改动调用方。
- 生成内容对齐 `ImportProtocolService`（`app/services/protocol_importers/import_protocol_service.rb`）的 `steps_params` schema（name/position/description/tables_attributes），直接喂入落库，不碰核心创建逻辑。
- 协议落点为**协议模板草稿**（draft template），用户审核/编辑后再导入项目。
- 权限文件置于 addon `app/permissions/**/*.rb`，由 `config/initializers/canaid.rb` 自动发现。
- 影响 / 风险：若上游未来自行实现并消费 `ai_parser_enabled?`，本 addon 通过 `app/decorators` / `app/overrides` 对核心视图/行为的覆盖可能产生冲突 —— 覆盖点须记录在配套开发计划（`docs/agents/ai-protocol-addon-plan.md`）并随上游演进复核。
- 关联：`docs/agents/addon-dev-workflow.md`（addon 方法学）、`docs/agents/ai-protocol-addon-plan.md`（PRD / Issues）。

### ADR-007：21 CFR Part 11 电子签名以 addon 形式实现（esignatures）
- 依据：官网「Regulatory Compliance / 21 CFR Part 11」明确要求电子签名须 *unique to one individual and indisputably linked to the respective electronic record… prevent fraudulent use*；代码库现状为全仓 0 命中 `electronic_signature` 模型/服务/UI（"esign" 命中均为 designate/design 字样），属完全缺失。
- 决策：以独立 Rails Engine `addons/esignatures/`（`Scinote::Esignatures::Engine`，`isolate_namespace`）承载全部电子签名逻辑；**绝不修改核心 `app/`**。
- 范围（PRD 见 `docs/PRODUCT_GAP_AND_PLAN.md` Addon A）：用户在协议（Protocol）/ 结果（Result）/ 实验（Experiment）上发起签名 → 系统记录签名人、时间戳、意图声明（meaning），并与目标记录**强绑定、不可篡改、可验证**。
- 数据模型（addon 自有迁移，不碰核心表）：
  - `e_signatures`（策略配置：适用实体列表、是否强制 meaning、是否需二次确认）通过 `Extends` 合并注册，禁止改 `config/initializers/extends.rb` 本体。
  - `e_signature_records`（签名事件）：`signable_type`/`signable_id`（多态）、`user_id`、`signed_at`、`meaning`、`record_hash`、`signature_hash`；**无 update/delete 路径**（append-only，应用层不可变）。
- grill 逼出的关键决策（设计前假设）：
  - **不可抵赖性**靠 `record_hash = H(record 内容 + user_id + signed_at + meaning)` 实现；`signature_hash = H(record_hash + 上一记录 hash)` 形成追加式哈希链（与 ADR-008 审计链可共用原语）。
  - **WORM 物理不可篡改**超出自托管范围（需 DB/存储层能力），本 addon 仅在应用层强制不可变，并在导出/校验中给出完整性证明；残留风险需在 rebase 时复核。
  - **入口不碰核心**：核心协议/实验页的「签名」按钮经 **deface**（`addons/esignatures/app/overrides/*.rb`，`insert_after 'div.content-header'`）注入服务器渲染的 header；`app/decorators/` 仅用于把 `SignatureHelper` 混入 `ApplicationHelper`。结果（Result）签名在 Vue canvas 内，需 JS 入口、留作后续。权限 `can_sign_record?` 等置于 `addons/esignatures/app/permissions/**/*.rb`，由 `config/initializers/canaid.rb` 自动发现。
  - **核心写路径不变**：签名是叠加行为，不修改被签名记录本身；仅读取其当前内容计算哈希。
- 签名服务：`Scinote::Esignatures::SignatureService.call(record:, user:, meaning:)` 生成带时间戳+哈希的签名记录，写入不可变存储。
- 验证与导出：提供哈希链完整性校验工具（CLI/rake task）；全量导出时附签名证明（关联 ADR-005 异步导出）。
- 影响 / 风险：若上游未来自行实现电子签名，本 addon 经 `app/decorators` 对核心视图的覆盖可能产生冲突 —— 覆盖点须记录在 `docs/PRODUCT_GAP_AND_PLAN.md` 并随上游演进复核。
- 关联：`docs/agents/addon-dev-workflow.md`（addon 方法学）、`docs/PRODUCT_GAP_AND_PLAN.md`（PRD / Issues A1–A4）。
- 现状（2026-09-01）：**已实现并接入**。实现与决策一致：签名服务 / 策略 / 完整性校验 / 导出证明均落在引擎内、未改核心 `app/`；canaid 权限经 `app/permissions` 真正注册。`engine.rb` 须显式 `config.eager_load_paths << root.join('app', 'permissions')`——引擎 `app/*` 子目录默认**不在** `eager_load_paths`，否则 canaid 扫描不到、调用即 `ArgumentError: unknown permission`。迁移初版版本号 `20260901000000` 与核心冲突且不被 Rails 纳入迁移扫描，已改为 `db/migrate/20260901001000_scinote_esignatures_create_tables.rb` 并并入 `db/structure.sql`（详见 `PRODUCT_GAP_AND_PLAN.md`「实施进度」踩坑条）。
- **单一改动面外溢登记（铁律 §〇）**：上述迁移直接落在宿主 `db/migrate/20260901001000_scinote_esignatures_create_tables.rb`，而非 addon 内 `append_migrations` 模式——属「只收敛进 `addons/esignatures/`」的已知例外（DB 层外溢）。rebase 上游时须将该文件视为宿主改动点单独核对迁移版本冲突；后续新 addon（如 `ai_eln`）已明确改用 `append_migrations` 落地自有表、宿主 `db/migrate` 零改动，**勿复制本特例**。

### ADR-008：Project Insights（科学项目管理仪表盘）以 addon 形式实现
- 依据：官网「Scientific Project Management / Project Insights」页四大 Widget（状态饼图 / 团队负载堆叠柱图 / 瓶颈检测 7·14·30+ 天 / 截止日期跟踪）；代码库现状为全仓 0 业务级 `insights` 代码（仅 vendor CSS 一处命中字样）。但约 70% 基础已具备：
  - `config/initializers/extends.rb:215` `DEFAULT_DASHBOARD_CONFIGURATION`（**Array**，含 `partial/visible/size/position`），dashboard 配置驱动渲染，`app/views/dashboards/show.html.erb:10-14` 遍历 `render partial: widget[:partial]`。
  - `MyModule`：`my_module_status_id`、`designated_users`（my_module.rb:76）、`overdue` 作用域(:85)、`is_overdue?`(:288)、`is_one_day_prior?`(:300)、`updated_at`；`.active` = `archivable_model` 的 `where(archived: false)`（app/models/concerns/archivable_model.rb:9）；`completed?` 谓词（终态状态，其 `my_module_status_consequences` 含 `MyModuleStatusConsequences::Completion`）。
  - `Dashboard::CurrentTasksController#load_tasks`（current_tasks_controller.rb:97-147）示范完整过滤链：`MyModule.active.readable_by_user(current_user, current_team).joins(experiment: :project).where(archived: false)`；widget 为 **erb 外壳 + AJAX 取 JSON** 模式（局部 `_current_tasks.html.erb` 用 `data-ajax-url=..._dashboard_current_tasks_path`）。
  - `package.json:63` `echarts ^6.0.0` 及 `:94` `vue-echarts ^8.0.0`；`app/javascript/packs/vue/design_system/charts.js` 含与官网一致的饼图 + 堆叠柱图 **echarts `option` 配置**（但仅挂在 `#charts` 的 Vue demo 入口，未被任何视图引用）。
- 决策：以独立 Rails Engine `addons/project_insights/`（`Scinote::ProjectInsights::Engine`，`isolate_namespace`）承载全部 Project Insights 逻辑；**绝不修改核心 `app/`**。本 ADR 决策经 `/grill` 逼问确认（见 `docs/project-management/实现现状与开发计划.md` 第三节）。
- 接入方式（不改核心，已 grill 校正）：
  - **Widget 注册（数组追加，非 merge!）**：`DEFAULT_DASHBOARD_CONFIGURATION` 是 **Array**，addon 在自身 `initializer` 中以 `Extends::DEFAULT_DASHBOARD_CONFIGURATION.concat([...])` / `<<` 追加 4 个 widget 配置项（含 `partial/visible/size/position`），**禁止改 `extends.rb` 本体**、不预置 `position`（避免与 `extends.rb` 注释警告的顺序依赖冲突）。
  - **灰度门控（AddonSetting 契约，opt-out）**：widget 仅在 `Scinote::ProjectInsights.enabled?`（读 `AddonSetting.enabled?('project_insights')`，无设置行时按"已挂载即默认启用"）为真时注册。**⚠️ 与本 ADR 初版/原计划不同**：初版写读 `ENV['PROJECT_INSIGHTS_ENABLED'] == 'true'`，该方案已被 **ADR-013**（Addon 配置自声明机制）取代——addon 改用 `AddonSetting` 表做实例级开关 + 参数（`default_period_days`），不再依赖 ENV。关闭即不注册、零渲染零查询。**不设 `visible: false` 常驻**，避免空容器。
  - **权限（复用，不加新权限）**：dashboard 本身已登录门控（current_tasks/calendar 均未单独授权）；本 addon **不新增** `can_view_project_insights?`，少一个改动面。
  - **聚合服务** `Scinote::ProjectInsights::AggregatorService`：复用 `MyModule.active.readable_by_user(current_user, current_team).joins(experiment: :project).where(projects: {archived: false}, experiments: {archived: false})`；瓶颈检测排除 `completed?` 任务（非 `state: completed` 列）；截止分桶现算——逾期=`is_overdue?`、今天=`due_date.to_date == Date.current`、本周=落在当前周、即将=之后（**无 `approaching_due_dates` 作用域**，计划原引 `:135` 错误）；状态流动态取——查询 `MyModuleStatusFlow`（`team_id = current_team` 且 `visibility: :in_team` 的团队流 ∪ `visibility: :global` 的全局流），再取其 `my_module_statuses` 的 `name`/`color`。**⚠️ `Team` 模型无 `my_module_status_flows` 关联**（初版/计划草案此处表述错误，已于 2026-09-01 实证校正，见 `docs/project-management/实现现状与开发计划.md` 第三节第 9 点）。
  - **图表（复用 echarts option 配置，新建 addon pack）**：复制 `charts.js` 的饼图/堆叠柱图 **`option` 对象形状** 到 addon 自有 pack `insights_charts.js`，在 `turbolinks:load` 时遍历 `[data-insights-chart]` 元素、读 addon JSON 端点数据初始化 echarts；**不改核心 `charts.js`**（其为独立 Vue demo，不能直接嵌入 erb dashboard）。
  - **下钻（复用 current_tasks 过滤）**：各 widget 区块链接到 `dashboard_current_tasks_path`（带 `statuses[]`/`mode`/`sort`/`project_id` 等预设过滤参数），不新建任务列表页。
- 影响 / 风险：若上游未来自行实现 Insights，本 addon 经 `Extends` 注入的 widget 配置与潜在的 `app/decorators` 覆盖可能冲突 —— 覆盖点须记录在 `docs/project-management/实现现状与开发计划.md` 并随上游演进复核；状态流可定制（聚合须动态查 `MyModuleStatusFlow`：团队自有流 + global 流）、大团队聚合须对 `updated_at`/`due_date`/`my_module_status_id` 建覆盖索引或缓存、截止日期按 **UTC**（`Time.current.utc`，与核心 `overdue` 作用域一致；`Team` 无时区字段）；per-team 灰度（非 deploy 级）为后续扩展，需经 `decorator` 或在 `settings` 加键，本期不做。
- 关联：`docs/agents/addon-dev-workflow.md`（addon 方法学）、`docs/project-management/实现现状与开发计划.md`（PRD / Issues P1–P9，已 grill）、`docs/project-management/README.md`（官网特性总结）、`docs/FEATURE_FLAGS.md`（ENV 类开关约定）。

### ADR-009：SciNote Templates（模板）现状确认 + Item Templates 以 addon 实现
- 依据：官网 [SciNote Templates](https://www.scinote.net/product/scinote-templates/) 六大模板类型（实验/工作流、协议/SOP、Forms、物料、结果、库存）；代码库现状为五大类均已落在核心 `app/`（证据见 `docs/templates/实现现状与开发计划.md` 第二节）。其中官网 "Automatically prompt users to use correct pre-approved reagents, instruments, kits" 的**自动提示行为已由核心实现**：协议库「Items」工具条（`app/views/protocols/_header.html.erb:28`，`data-e2e="e2e-BT-protocolTemplates-topToolbar-items"`）可为协议挂库存项（`ProtocolRepositoryRow`，`app/models/protocol_repository_row.rb`），`Protocol#load_from_repository`（`app/models/protocol.rb:627`）实例化到任务时 `clone_contents(include_assigned_rows: true)`（`:639`）把 `protocol_repository_rows` 拷贝为 `my_module_repository_rows`（`:447-463`）。**唯一缺口是把「一套预选库存」抽象成命名、可复用、可绑定多协议的一等公民对象，以及可选 `required` 强制标志**（全仓 0 命中 `item_template` 命名概念）。
- 决策：以独立 Rails Engine `addons/protocol_item_templates/`（`Scinote::ProtocolItemTemplates::Engine`，`isolate_namespace`）承载 Item Templates 的**命名可复用抽象增强**（不重写核心自动带入逻辑）；**绝不修改核心 `app/`、不新增 `protocol_repository_rows` 表列**。命名模板与协议的绑定存 addon 自有迁移表，经 `Extends` 合并注册（`config/initializers/extends.rb` 本体不改）；绑定服务在绑定期将命名模板的预选 `repository_rows` 展开写入既有 `protocol_repository_rows`（复用 `ProtocolRepositoryRow` 模型），实例化到任务的自动带入仍完全由核心 `protocol.rb:447-463` 负责。可选 `required` 标志存 addon 自有表。
- 影响 / 风险：若上游未来在核心实现自有 Item Templates，本 addon 的 `to_prepare` 装饰 / `app/decorators` 可能重复触发 —— 覆盖点须记录在 `docs/templates/实现现状与开发计划.md` 并随上游演进复核。
- 关联：`docs/agents/addon-dev-workflow.md`（addon 方法学）、`docs/templates/README.md`（官网特性总结）、`docs/templates/实现现状与开发计划.md`（PRD / Issues T1–T5）。
- 序号说明：本 ADR 占用 ADR-009；`docs/protocol-sop-management/实现现状与开发计划.md` 中预留的「库协议版本通知」ADR 顺延为 **ADR-010**（其 ADR-009 引用已于 ADR-010 落盘时同步更新）。

### ADR-010：协议库版本变更通知以 addon 形式实现（protocol_version_notifier）
- 依据：官网「Protocol & SOP Management」明确「If the version in the repository changes, you will be notified」；代码库现状为——`Protocol` 已具备版本体系（`in_repository_published_original` / `published_version`、`version_number`、`newer_than_parent?`、`revert_protocol` 权限，`app/models/protocol.rb:22-31,491`、`app/permissions/protocol.rb:96-103`），但**全仓无任何「协议版本变更 → 通知关联任务」的服务 / observer**（搜索 `ProtocolUpdated`/`notify`/`protocol.*changed` 0 命中），仅提供手动 revert 能力。即「库版本变更通知」为**真实缺失项**。
- 决策：以独立 Rails Engine `addons/protocol_version_notifier/`（`Scinote::ProtocolVersionNotifier::Engine`，`isolate_namespace`）承载全部版本变更通知逻辑；**绝不修改核心 `app/`**。
- 触发与接收（复用，不新建基础设施）：
  - 订阅 `Protocol` 的版本变更事件——优先复用 `Protocol` 已 `include ObservableModel`（`app/models/protocol.rb:17`）的广播能力；若其不对外发 `ActiveSupport::Notifications`，则改用引擎 `to_prepare` 装饰 `Protocol` 的发布动作（deface 式，不改核心本体）。
  - 接收人取 `Protocol#all_linked_children`（`protocol.rb:340-344`）→ `linked_my_modules` → 任务 `designated_users`（`my_module.rb:76`），并经 `can_read_protocol_in_repository?` 过滤；推送复用 `Activities::CreateActivityService` 与 `app/notifications/`（参考 `repository_item_date_notification.rb`），不另造渠道。
  - UI 提示经 `app/decorators` 注入任务协议面板，受 `newer_than_parent?` 驱动；「一键 revert」完全依赖核心既有 `revert_protocol` 权限与逻辑，addon 不重写。
- 范围边界（经 `/grill` 待确认）：本期**仅**做 G1 版本变更通知；**G2 重新定性**——步骤完成人实际已由 `complete_step`/`uncomplete_step` 活动（`extends.rb:285-286`）以 `owner = current_user` 记录（`steps_controller.rb:367-393,580-588`），数据层已满足「由谁完成」，仅 UI 未内联展示，可由 addon 侧读取 `activities` 实现、**无需改核心**；独立的 `completed_by` 列不推荐（需核心迁移，违反 addon 铁律）。**不承接** G3（SciNote Edit 为外部桌面程序，本仓已有「本地程序打开」接入点）。与「AI 辅助创建协议」相关的绿地工作属独立 `ADR-006`（`addons/ai_protocols`），不在此重复。
- 影响 / 风险：若上游未来在核心实现自有版本通知，本 addon 的 `to_prepare` 订阅 / decorator 可能重复触发——覆盖点须记录在 `docs/protocol-sop-management/实现现状与开发计划.md` 并随上游演进复核；同一协议多次发布需去重，避免刷屏。
- 关联：`docs/agents/addon-dev-workflow.md`（addon 方法学）、`docs/protocol-sop-management/README.md`（官网特性总结）、`docs/protocol-sop-management/实现现状与开发计划.md`（PRD / Issues P1–P4）。

### ADR-011：Team Management 现状评估——核心已实现，仅外部计费/报告为 addon 候选
- 依据：官网 [Team Management](https://www.scinote.net/product/team-management/) 6 大能力 + 代码探查。团队/角色/权限/邀请/`#`@ 协作/任务分配/Overview·日历/报告/电子签名(addon)/时区/审计 **已在 fork 实现**（逐项证据见 `docs/team-management/实现现状与开发计划.md` 第二节表）。核心 `app/` 搜 `billing`/`accounting`/`invoice`/`RESTful` 0 命中。
- 决策：
  1. **不在 fork 重建**核心 Team Management（违反 addon 铁律且收益为零）。
  2. **W1（团队细分 / 限制访问 ELN 特定部分）判为上游计划级**：OSS fork 无 `parent_team`/`child_team`（`app/models/team.rb` 搜索 0 命中），需改造核心 `team.rb` + `readable_by_user` 链，**本 fork 不承接**。
  3. **W2（外部伙伴/客户报告与计费 REST API 自动化）** 以独立引擎 `addons/partner_reporting/`（`Scinote::PartnerReporting::Engine`，`isolate_namespace`）承载，**绝不改核心 `app/`**；复用 `reports_controller` 导出 + `users/settings/webhooks_controller.rb` 雏形 + `Extends` 合并 + `app/permissions/**/*.rb` 自动发现；聚合复用 ADR-008 的 `readable_by_user.joins(experiment: :project)` 范式；对外 API 客户端参考 `biomolecule_toolkit_client.rb`。
- 影响 / 风险：W2 对外 CRM/ERP 契约未定（须 grill 明确字段/认证）；W1 强行 addon 化会突破铁律、rebase 冲突极高。W2 覆盖点仅限 addon 内，rebase 冲突低。
- 关联：`docs/agents/addon-dev-workflow.md`（addon 方法学）、`docs/team-management/README.md`（官网特性总结）、`docs/team-management/实现现状与开发计划.md`（PRD / 缺口 W1–W2）、ADR-003/ADR-005/ADR-007/ADR-008。

### ADR-012：Integrations & API 现状评估——核心已实现 8 项，3 项外部集成为 addon 候选
- 依据：官网 [Integrations & API](https://www.scinote.net/product/integrations-and-api/) 罗列 1 个 RESTful API + 11 项开箱集成；代码库核查（逐项文件:行证据见 `docs/integrations-api/实现现状与开发计划.md` 第一节）。
- 已实现（核心 `app/`，非 addon，不重建）：RESTful API（`app/controllers/api/v1` 40 控制器 + `app/controllers/api/v2` 21 控制器，对外文档 `scinote-api-docs/`）、Webhooks（`app/controllers/users/settings/webhooks_controller.rb`）、Protocols.io 导入（ADR-002）、Office for the Web / WOPI（`wopi_controller.rb` + `wopi_discovery.rb`）、Open Vector Editor（`app/javascript/vue/ove/OpenVectorEditor.vue`）、ChemAxon Marvin（`marvin_js_service.rb`）、Zebra 标签打印（`label_printers_controller.rb` + `zebra_label_template.rb`）、FLUICS 云打印（`label_printers/fluics/sync_service.rb`）。
- 缺失（全仓 0 命中）：Ganymede、Quartzy、Gilson Connect。
- 决策：
  1. **不在 fork 重建**上述核心集成（违反 addon 铁律且收益为零，与 ADR-008/009/011 同口径）。
  2. 三项缺失集成若决定承接，**各自以独立 Rails Engine addon**（`Scinote::Ganymede::Engine` / `Scinote::Quartzy::Engine` / `Scinote::GilsonConnect::Engine`，`isolate_namespace`）实现，**绝不改核心 `app/`**；复用 FLUICS 的 `api_client`+`sync_service` 云同步范式、`label_printers_controller` 设置页 UI 范式、`results_controller`/`inventories_controller` API 写入、以及 `activities` 记录范式。
  3. 三项均涉第三方认证 / 数据契约 / 合规，须经 `/grill` 明确字段映射后再脚手架；建议先做单向数据流入 MVP，避免范围膨胀（Ganymede 为「全实验室自动化平台」，风险最高）。
- 影响 / 风险：本环境（Windows，无 GitHub / 外网代理）无法对三项做第三方联调，仅能离线写客户端与契约测试；若上游未来原生实现这些集成，本 addon 的 `Extends` 合并 / decorator 可能重复触发（参照 ADR-006~011 的冲突提示）。
- 关联：`docs/agents/addon-dev-workflow.md`（addon 方法学）、`docs/integrations-api/README.md`（官网特性总结）、`docs/integrations-api/实现现状与开发计划.md`（现状表 / 缺失项 addon 形态 / 里程碑）。

### ADR-013：Addon 配置自声明机制（设置页开启 + 参数，由各 addon 以 schema 自治暴露）
- 依据：用户诉求「addon 配置项应明确反映在设置页，addon 需有机制把自身所需设置项目暴露到 addon 设置页」；代码库现状为 `AddonSetting#configuration` 是**自由 JSON**，设置页用**裸 `text_area` 手填 JSON**——无结构、无类型、无各 addon 自描述，每新增 addon 参数都要改设置页/模型硬编码。本决策即"配置参数页面也应**实现为 addons**"的落地范式。
- 决策：建立"addon 自声明 `config_schema`"的通用机制，**绝不修改核心 `app/` 来逐个 addon 硬编码字段**：
  - **自治暴露（核心范式）**：每个 addon 在其模块上定义 `self.config_schema`，返回字段数组（每字段含 `key` / `label` / `type` / `default?` / `options?` / `help?`）；设置页读取 `AddonSetting.config_schema_for(name)`（`Scinote::#{Name}.config_schema`，模块不可达时安全返回 `[]`，此时仅渲染启用开关），按 `type` 动态渲染类型化控件，并据各 addon 自有 `config/locales` 的 i18n 键显示标签/帮助。
  - **类型契约**：`type ∈ {boolean, string, integer, secret, text, select}`；`select` 需 `options: [{label:, value:}]`；`AddonsController#typed_configuration` 提交时按字段类型化写入 `addon_settings.configuration`（JSONB）。
  - **仅新增机制，不迁移既有配置源**：ai_protocols 既有从 `ENV['AI_PROTOCOLS_*']` / `ApplicationSettings` 读取的逻辑保持不变；新机制只"新增"暴露入口，运行时尚不强制改用 `AddonSetting`（运行时消费为后续跟进，见影响/风险）。
  - **secret 约定**：secret 类字段不在表单回显，留空即保留原值（见 `typed_configuration` 的 secret 分支与 `render_addon_config_input` 的 password 控件）。
  - **i18n 自洽**：标签/帮助键置于各 addon 自有 `config/locales/{en,zh-CN}.yml`（引擎自动加载），不写入核心 locale。
  - **兼容旧契约**：`typed_configuration` 仍接受裸 JSON 字符串（整体原样存储），不破坏既有数据。
- 影响 / 风险：若某 addon 声明了 schema 但运行时尚未消费（如 ai_protocols 已声明 `parser_url`/`api_key`/`model`，但首轮仅暴露未消费），则设置页可填但暂未生效——该缺口由 Issue #3（ai_protocols）与 Issue #4（project_insights `default_period_days`）跟进补齐；核心 `AddonSetting#config_schema_for` 必须持续保证**安全降级**（模块不可达返回 `[]`），否则未声明 addon 的设置页渲染会报错。本机制为实例级（`AddonSetting`），不涉及团队级覆盖。
- 关联：`docs/agents/addon-dev-workflow.md`（addon 方法学）、`docs/addons-config/PRD.md`（PRD）、`docs/addons-config/issues.md`（Issues #1–#5：核心机制 / 三 addon 播种 schema / 运行时消费跟进 / 打磨）。已落地部分：Issue #1（通用机制）、#2（三 addon 播种 schema）、#3（ai_protocols 运行期经 `Scinote::AiProtocols.llm_client` 消费配置，回退 ENV）、#4（project_insights `default_period_days` 作为瓶颈陈旧阈值，UI 标签动态化）、#5（关闭时禁用字段 / 整数≥0 校验 / secret 已设置指示）均已实现并通过测试。
- 设置页 addon 化收尾（2026-09-02）：设置页 UI（controller/view/helper/locale）已抽离至 `addons/addon_settings` 引擎（见 `docs/addons-config/refactor-addonize-settings-issues.md` Issue 1–2 与 `docs/addons-config/refactor-addonize-settings-PRD.md`）；`AddonSetting` 模型、`20260901130000_create_addon_settings` 迁移、`InstanceAdmin` 权限（`app/permissions/instance_admin.rb` + `app/services/instance_admin.rb` 的 `:manage_addons`）作为**底座留核心**（鸡生蛋例外，非铁律违反），不随设置页 UI 一并 addon 化。引擎经 `app.routes.append { mount Scinote::AddonSettings::Engine => '/' }` 自注册路由（引擎内 `config/routes.rb` 定义 `addons` GET 与 `update_addon` PUT，且**未用 `isolate_namespace`** 以保持 `addons_path` 等宿主命名空间 helper），核心 `config/routes.rb` 不再含设置页路由；卸载 addon（撤 Gemfile 一行）后主程序启动正常（路由未注册即 404，无崩溃）。

### ADR-014：AI-ELN 插件以独立 Rails Engine 实现（零侵入、复用 ai_protocols 的 LLM 客户端）
- 依据：用户需求规格 `AI-ELN 需求规格文档 V1.0`（25 项 AI 功能：实验辅助 / 文档图谱解析 / 配方处理 / 语义检索 / GLP 合规自检 / 多语言）；代码库核查见 `docs/ai-eln/实现现状与开发计划.md` §0。关键事实：`addons/ai_protocols` 已用 `Scinote::AiProtocols::LlmClient`（OpenAI 兼容，天然兼容 Ollama 本地部署）实现「文本/PDF→规程模板」（对应 spec 的 AI-201/AI-101 子集）；addon 零侵入范式（engine 自注册路由 + Gemfile 注释即禁用 + `append_migrations` + deface/decorator 注入）已多次验证。
- 决策（4 项承重决策，经 /grill 与用户拍板）：
  1. **独立引擎、并列共存**：新建 `addons/ai_eln`（`Scinote::AiEln::Engine`，`isolate_namespace`），与 `ai_protocols` 并列，不合并、不替代；复用 `ai_protocols` 的 `LlmClient`（D1）。两者同时挂载时 ai_eln 直接引用该常量，monorepo 下可接受（易逆转，不当作铁律冲突）。
  2. **地基优先**：首个垂直切片做引擎骨架（自注册路由 + `append_migrations` + `can_use_ai_eln?` 权限 + `LlmAdapter` + `AuditLogger` + 三表 `ai_eln_ai_sessions/interactions/audit_logs` + 侧边抽屉外壳 + 全局开关），后续 25 功能挂其上（D2）。
  3. **配置用 ENV + ApplicationSettings 特性开关**：`ai_eln_enabled`（DB `ApplicationSettings#values`，由新建独立迁移置 `true`）+ `AI_ELN_PARSER`（ENV）双判定；**不引入 YAML 配置**（D3）。沿用 ai_protocols 已验证范式，可热切换、关 AI 不改代码。
  4. **引擎自有表走 `append_migrations`**：三表迁移置于 `addons/ai_eln/db/migrate`，经脚手架 `append_migrations` initializer 追加进 host 迁移路径，**宿主 `db/migrate` 零改动**（D4）。esignatures 那次直接塞宿主 `db/migrate` 属特例，不沿用。
- 合规约束（贯穿全部切片）：AI 输出一律 HITL——预览 + 显式确认，禁止自动写 host 原始记录；每次调用落 `ai_audit_logs`；关闭开关后整体退化为原生 SciNote。
- 影响 / 风险：ai_eln 与 ai_protocols 的 LLM 客户端为共享耦合，若未来禁用 ai_protocols 需同步处理（易逆转）；AI-102 OCR 引擎、P12/P13 语义检索 v1 形态、审计迁移命名等仍有待确认项，见 `实现现状与开发计划.md` §10。向量数据库（spec §8.1）明确推迟。

### ADR-015：贝叶斯配方优化（AI-501）数据来源与计算后端
- 状态：规划（proposed）｜ 关联：`实现现状与开发计划.md` §12、CONTEXT.md §五/§六
- 背景：spec 原 §8.2「贝叶斯优化闭环」此前列为非范围；现纳入范围。需确定训练数据从 SciNote 何处读取、候选如何产出（且生成 draft 不得扣库存）、计算后端形态。
- 决策：
  1. **指标 + 工艺参数**统一从 `my_module` 的 `ResultTable` 命名列读取（按列名匹配），**不引入新 measurements 表**（spec 假想表不存在）。
  2. **抽样单元 = `my_module`（`status=completed`）**：一条样本 = 该任务经 `MyModuleRepositoryRow` 挂接的 RepositoryRow 的 `stock_consumption` 组分向量 + 其 ResultTable 指标/工艺向量。
  3. **配方/组分质量份映射 = 方向 X（鹰谷-lite，无配方实体表）**：基准配方 = SciNote 实验模板（`CopyExperimentAsTemplateService`），实验配方 = 克隆实验内 `MyModuleRepositoryRow#stock_consumption`（组分质量份），工艺/性能 = `ResultTable` 命名列；变量/固定区分经轻量「优化配置」（per 基准模板记变量组分 + 上下界）。抽取经可配置 `RecipeAdapter` 抽象，default 即方向 X 适配器；真实结构变更（如改方向 Y 建配方表）仅新增 adapter 子类，核心不写死。（**状态：2026-09-03 已锁定方向 X**）。
  4. **计算后端 = 纯 ruby（无 python）**：默认 `Numo::NArray` 做矩阵运算 + 自实现高斯过程（RBF/Matern 核 + Cholesky 求解），采集函数 EI/UCB，单目标优先。
  5. **候选产出（方向 X）= 表格预览 + 人工粘贴**：候选以表格呈现（组分质量份 + 工艺参数，标注预测均值±方差），**不自动建实验、不进入 `MyModuleRepositoryRow` / stock 路径**，用户确认后人工粘贴到从基准模板克隆的实验（HITL）→ 满足「生成候选不扣库存」约束。
- 影响 / 风险：纯 ruby GP 对多目标与硬约束支持弱（v1 仅单目标稳健，多目标用加权标量化近似）；样本需 ≥~8 条才有意义；`Numo` 为新增纯 ruby gem（零 python）；配方映射已定方向 X（无配方实体表），变量/固定区分经轻量「优化配置」（见 §12.2）。AI-501 不调 LLM，纯数值，审计照落 `ai_audit_logs`。
- 关联：`docs/ai-eln/CONTEXT.md`（术语表）、`docs/ai-eln/实现现状与开发计划.md`（P1–P17 Issue 拆分）、`docs/agents/addon-dev-workflow.md`（addon 方法学）、ADR-006（ai_protocols）、ADR-013（addon 配置自声明）。

### ADR-016：Addon 路由自注册统一策略（engine initializer 自挂载，host 零修改）
- 背景（2026-09-02）：核对"高级：initializer 注入 mount，实现 application.rb 零字符修改"文档说法，确认项目在"零入侵"目标上与文档一致、具体配方有分歧，并统一 `addon_settings` 的路由注册机制。
- 决策（统一契约）：
  1. **全部 addon 路由均由各自 `engine.rb` 的 initializer 自注册**：`initializer 'scinote_<name>.routes', after: :add_routes do |app| app.routes.append { mount <Engine> => <mount_point> } end`；核心 `config/routes.rb` 与 `application.rb` 零 addon 路由/配置，仅 Gemfile 一行引入即生效、注释即禁用（启动正常，路由未注册即 404，无崩溃）。
  2. **"统一"统一的是机制，不是挂载路径**：所有 addon 走**同一套机制**——由各自 `engine.rb` 的 initializer 自挂载 `mount <Engine>`，且经 `after: :add_routes` 追加到宿主路由之后；host 的 `config/routes.rb` / `application.rb` 零侵入。至于"挂载到哪"（`mount_point`）是**各 addon 的本地决策，按 UX 场景而定，不必强求一致**：现状既有挂根 `'/'` 的（project_insights / ai_protocols / esignatures / addon_settings，引擎内用绝对路径定义终态 URL），也有挂宿主既有前缀的（i18n locale 挂到 `/users/settings/locale`）。**统一契约 = "都是 `mount Engine`"，不是"都挂到同一路径"**；是否集中到 `/addons/*` 等子路径属 §升级路径 级别的架构选择，当前 curated 规模（5 个 addon）下不强求。
  3. **`addon_settings` 由"裸 `app.routes.append { get/put }`"改造为正规挂载引擎**：新增 `config/routes.rb` 承载其 host 风格路由，并**保留 `isolate_namespace Scinote::AddonSettings`**（与 `i18n`/`ai_protocols`/`esignatures`/`project_insights` 一致）。其控制器已扁平化为 `Scinote::AddonSettings::AddonsController`（原长路径 `Users::Settings::Account::AddonsController` 已废弃），URL 仍为 `/users/settings/account/addons`。宿主代码（`app/views/users/settings/_sidebar.html.erb`、`navigations_controller.rb`、`label_printers_controller.rb`、features、specs 等 20+ 处）直接引用的 `addons_path` / `update_addon_path` 之所以在隔离后仍可用，是依靠 `engine.rb` 的 `config.to_prepare` 把这两个 helper 提升（promote）到宿主级（委托给引擎代理），而非保留宿主命名空间；因此隔离不会把 helper 改名、也不会破坏任何引用。
  4. **时序统一 `after: :add_routes`**：显式、防御性、与文档对齐；在 Rails 7.2.3.2 下 `app.routes.append` 不依赖该顺序也能工作，但显式声明规避"过早 RouteSet 未初始化 / 过晚已编译追加无效"的潜在坑。
- 避撞规则（硬约束）：每个 addon 必须独占一个唯一根路径前缀（现状已满足：`/insights`、`/ai_protocols`、`/esignatures/sign`、`/users/settings/locale`、`/users/settings/account/addons`）。因 addon 路由经 `after: :add_routes` 追加在**宿主路由之后**，若与宿主或他 addon 同路径同动词，宿主优先匹配 → addon 静默 404（路由遮蔽）。新增 addon 须先校验路径不与既有冲突。
- 升级路径：若未来引入第三方 / 社区 addon 或路径重叠风险升高，改用子路径挂载 `mount <Engine> => '/<addon>'`（引擎内路由相应改为根路径，对外 URL 基本不变），以彻底隔离命名空间。当前 curated 规模（5 个 addon）下根挂载可接受。
- 影响 / 风险：根挂载共享根命名空间，碰撞靠"唯一前缀约定"而非结构保障（脆弱现状）；升级路径见上。各 addon 覆盖点（deface / decorator）仍须随上游演进复核（沿用 ADR-006~015 冲突提示）。
- 关联：ADR-013（addon 配置自声明 / 设置页 addon 化）、ADR-006 / 007 / 008 / 009（各 addon 实现）、`docs/agents/addon-dev-workflow.md`（addon 方法学）。

## 四、复杂度热点（维护风险）
| fan_in | 符号 | 风险说明 |
|---|---|---|
| 819 | `LabelTemplates::RepositoryRowService#render` | 触及每个仓库行的渲染；改动波及面极广 |
| 421 | `ProtocolImporters::ProtocolsIo::V3::StepComponents#name` | 与外部格式强耦合 |
| 243 | `BiomoleculeToolkitClient#create` | 外部服务客户端；存在网络/可用性风险 |
| 228 | `ModelExporters::TeamExporter#team` | 导出面大 |
| 177 | `SmartAnnotations::TagToHtml#parse` | 核心文本/注解转换；对 XSS 转义敏感 |

## 五、功能聚类（高内聚模块）
1. 仓库行渲染 + 过滤 + 智能注解（render / repository_rows / repository_row / value / tag_to_html）。
2. 协议导入导出 + 步骤 + 结果（protocol / step / name / result / custom_auto_link）。
3. 团队 / 项目 / 实验 / 模块层级（team / project / merge / experiment / my_module）。
4. 权限 + `readable_by_user` 校验。
5. 资源/二进制/元数据存储（blob / metadata / filename / content_type）。

## 六、后续开发的防护建议
- 将 `repository_*` 与 `permissions/*` 视为稳定性关键区域；重构前先补充刻画性测试。
- 新增实体：按约定同时补齐 模型 + 序列化器 + 控制器 + 权限文件 + factory + spec（图谱显示它们按约定强耦合）。
- 导出/通知逻辑应放在 `app/jobs` 与 `app/services`，而非控制器中。
- `parse_partial` 覆盖缺口存在于 Dockerfile、Makefile 与 `.scss` 文件 —— 均非核心；核心 Ruby/Vue 覆盖完整（0 跳过）。

---

*本文档为 codebase-memory 工程库中持久化 ADR 的镜像
（`manage_adr(mode="get")` 可读）。发生重大架构变更后请重新生成。*
