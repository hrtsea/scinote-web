# 实验室库存管理（Inventory Management）功能梳理与实现现状

> 来源页面：https://www.scinote.net/product/inventory-management/
> 整理时间：2026-09-01
> 术语对应：官网「Inventory / Inventory item」在本 fork 代码中对应 **Repository / RepositoryRow**（仓库 / 仓库条目）。
> 说明：本文件在 `docs/PRODUCT_OVERVIEW.md`（官网产品总览）基础上，聚焦「库存管理」单页，逐条对照本 fork 的实现现状，并给出缺口与开发计划。

---

## 〇、总览结论

本 fork（`scinote-web`）对官网库存管理页描述的**全部主线能力均已实现并默认开启**（见 `docs/FEATURE_FLAGS.md`：
`stock_management_enabled`、`repository_row_connections_enabled`、`equipment_booking_enabled`、
`storage_locations_enabled`、`forms_enabled`、`user_groups_enabled` 等均由迁移 `20260830120000_enable_feature_flags.rb` 置为 `true`）。

逐条核对后，库存管理域内的**真正缺口很少**（详见第三节），主要是少量「官网描述为可填信息项、但本 fork 未做成独立结构化类型」的点，以及官网同页提及但属于独立产品的「移动端 App」。因此开发计划以「补齐结构化缺口 + 增强」为主，而非从零建设。

---

## 一、官网功能逐条梳理

官网将库存管理的能力归纳为五大块，逐块摘录如下。

### 1. MANAGE WHAT YOU USE IN THE LAB（管理实验室中使用的东西）

> 管理并追踪实验室里用到的所有东西——从试剂、样本到耗材与仪器。按需自定义列，附加文件（产品说明书、手册、MSDS）。通过设备调度器预约仪器，在集中数据库中快速找到一切。

细分示例：
- **Samples & Reagents（样本与试剂）**：在专用集中仓库中管理 ID、描述、存储位置、相关文档、状态、可用性等信息；连接相关条目、建立样本谱系（sample lineages）；把样本指派给任务以关联结果与协议。
- **Reagents（试剂）**：建立实验室/全组织试剂中心仓库，记录库存、再订货详情、SKU、MSDS 文档、配方（recipes）、位置、批号/批次（lot/batch）信息；通过条目关系分组；连接到协议与结果保证可追溯。
- **Primers and plasmids（引物与质粒）**：建立引物/质粒数据库，添加序列、厂商、文献引用、公共数据库链接，甚至包含质粒图谱（plasmid maps）；在实验中引用以回溯。
- **Instruments（仪器）**：记录仪器用于执行哪个协议、哪些样本在其上运行；建立组织级共享仪器数据库；添加使用指南、校准与计划维护日期。

### 2. TRACK USAGE AND RECEIVE ALERTS（追踪用量并接收提醒）

> 库存管理功能自动监控实验室库存：实验中消耗的库存自动扣减，库存偏低时告警；日期提醒可通知试剂过期、仪器校准或样本监测。

### 3. BARCODES AND CUSTOM LABELS（条码与自定义标签）

> 为任意库存条目（样本、试剂）打印标签以标记试管、孔板、架子等容器；每个库存条目在 SciNote 中带有唯一二维码（QR code），可印入标签，扫一扫即定位全部信息。支持部分 Zebra 与 Fluics 标签打印机。

### 4. FULL TRACEABILITY（完整可追溯）

> 在实验任务、协议、结果中交叉引用库存条目，从而可回溯到带来最佳结果的试剂库存或样本批次；在评论中引用库存信息以促进讨论与协作。

### 5. TRANSITION FROM SPREADSHEET（从电子表格迁移）

> 将现有库存电子表格直接导入 SciNote 仓库：建空仓库 → 建列 → 上传文件 → 列映射；之后可继续编辑、追加批次导入，也可整体导出。需要数据库间同步/自动上传时，可用 API 实现。

---

## 二、实现现状对照表

状态图例：✅ 已实现并默认开启 ｜ 🟡 已实现但需开关/ENV ｜ ❌ 本 fork 未实现 ｜ ➖ 属独立产品/非本仓库范围

| # | 官网能力 | 本 fork 实现证据 | 状态 |
|---|---|---|---|
| 1.1 | 自定义列（文本/数值/列表/状态/勾选/日期/时间/区间等） | `RepositoryColumn` + 各 `*Value` 模型（`repository_text/number/list/status/checklist/date_time/..._value.rb`）、`repository_columns/create_column_service.rb` | ✅ |
| 1.2 | 附加文件（产品说明书/手册/MSDS） | `RepositoryAssetValue`、`form_repository_rows_field_value.rb`、资产上传 | ✅ |
| 1.3 | 设备调度器预约仪器 | `EquipmentBookingsController`、`CalendarEvent`、`equipment_bookings/*.vue`、`equipment_booking_enabled` | ✅ |
| 1.4 | 集中数据库 + 快速检索 | `RepositoryDatatableService`、`repository_datatable_helper.rb`、全局搜索 | ✅ |
| 1.5 | 样本 ID/描述/存储位置/文档/状态/可用性 | `RepositoryRow` + `RepositoryCell` + `StorageLocationRepositoryRow`（存储位置）、`storage_locations` 模块 | ✅ |
| 1.6 | 连接相关条目 / 样本谱系（lineages） | `RepositoryRowConnection`（parent/child）、`repository_row_connections_enabled`、`repository_item_relationships_sidebar.js` | ✅ |
| 1.7 | 样本指派给任务以关联结果与协议 | `MyModuleRepositoryRow`、`my_module/assigned_items/repository.vue` | ✅ |
| 1.8 | 试剂库存/再订货/SKU/批号批次 | `RepositoryStockValue`、`RepositoryStockUnitItem`、`repository_stock_unit_item_serializer.rb` | ✅ |
| 1.9 | 试剂「配方（recipes）」等信息项 | 官网将其与库存/SKU/MSDS/批号并列列为「可记录的示例信息之一」，非独立功能；可由「文本列」或「附件列（上传配方文档）」承载，无需独立类型（见第三节 G1 勘误） | ✅ |
| 1.10 | 引物/质粒序列、文献引用、公共库链接 | `GeneSequenceAsset`、`gene_sequence_assets_controller.rb`、`OpenVectorEditor.vue`、MarvinJS 编辑器 | ✅ |
| 1.11 | 质粒图谱（plasmid maps） | 同上（OVE 向量编辑器打开序列资产） | ✅ |
| 1.12 | 仪器：用于哪个协议/哪些样本 + 使用指南/校准/维护日期 | `RepositoryRow` 关联 `ProtocolRepositoryRow`；日期类列 + 日期提醒作业实现校准/维护提醒 | ✅ |
| 2.1 | 实验任务消耗库存自动扣减 | `RepositoryStockConsumptionValue`、`RepositoryLedgerRecord`、`consume_modal.json.jbuilder`、`my_module_status_consequences/repository_snapshot.rb` | ✅ |
| 2.2 | 低库存告警 | `LowStockNotification`、`repository_stock_value.rb` 阈值逻辑 | ✅ |
| 2.3 | 日期提醒（试剂过期/仪器校准/样本监测） | `RepositoryItemDateReminderJob`、`RepositoryItemDateNotification`、`HiddenRepositoryCellReminder`、`hide_repository_reminders_job.rb` | ✅ |
| 3.1 | 打印标签（试管/孔板/架） | `LabelPrintersController`、`label_templates/*`、`repository_print_modal`、`_print_label_button.html.erb` | ✅ |
| 3.2 | 每个条目唯一二维码 | 打印标签模态内置 QR（`repository_print_modal/container.vue`、`zebra_print.js`） | ✅ |
| 3.3 | Zebra / Fluics 打印机支持 | `LabelPrinter`（Zebra/Fluics 模型）、`label_printers/fluics/*`、`_zebra_settings.html.erb`、`_fluics_settings.html.erb`、`ENABLE_FLUICS_SYNC` | ✅ |
| 4.1 | 任务/协议/结果交叉引用库存 | `MyModuleRepositoryRow` + `ProtocolRepositoryRow` + `RepositorySnapshot`（任务快照固化库存） | ✅ |
| 4.2 | 评论中引用库存信息 | Smart Annotation 的 `_repository_items.html.erb`、`smart_annotation.rb#repository_rows`、`global_activities/references/_repository_row.html.erb` | ✅ |
| 5.1 | 电子表格导入（建列→上传→列映射） | `RepositoryImportParser::Importer`、`import_repository/*`、`vue_import_repository_modal.js` | ✅ |
| 5.2 | 整体导出（CSV/XLSX） | `RepositoryCsvExport`、`RepositoryXlsxExport`、`repository_zip_export_job.rb`、`repository_stock_ledger_zip_export.rb` | ✅ |
| 5.3 | API 同步/自动上传 | `CORE_API_V1_ENABLED` / `CORE_API_V2_ENABLED`（已 `true`）、`api/v1/*inventory*` 序列化器 | 🟡（API 可用；开箱同步代理不在本仓库） |
| — | ELN Mobile App（移动端） | 官网独立产品条目，非本 Web 仓库范围 | ➖ |

---

## 三、本 fork 的缺口（库存管理域内）

> 以下缺口均有代码证据支撑，避免主观臆断。其余官网能力均已覆盖。

### G1（勘误：非缺口）— 试剂「配方（recipes）」
- **勘误说明**：初版将「recipes」误判为缺失的结构化功能，特此更正。回看官网原文，该词出现在 *"Include information such as stock, re-order details, SKUs, MSDS documents, recipes, location, lot or batch info"* 一句中，与库存/SKU/MSDS/批号等并列，仅是「可记录的示例性信息项」。**官网并未描述任何「配方管理 / 物料清单(BOM) / 按配方倒扣组分」之类的独立功能。**
- **现状**：本 fork 的灵活自定义列体系（`RepositoryColumn` + 文本/附件列）已能承载此类信息——配方可作为文本列内容，或经附件列上传配方文档记录。因此这**不构成缺口**，原 P1 开发项已撤销。
- **遗留可选增强（非源自官网）**：若未来确有内部需求要做「配方成品消耗时联动倒扣组分库存」，可另行立项，但不在本官网对照任务范围内。

### G2 — 库存条目无「负责人（responsible user）」专属字段
- **官网描述**：开篇「Assign inventory responsibilities to team members」。
- **现状**：`RepositoryRow` 仅有 `created_by` / `last_modified_by`（见 `app/models/repository_row.rb:17-18`），无独立「负责人」字段；「责任」在系统中通过两层表达——仓库级团队权限（`permissions/repository.rb` 的 manage/read）与任务级 `designated_users`（`MyModule`）。这已覆盖「把库存责任分给团队成员」的主要语义，但缺少「单条目级负责人」维度。
- **影响**：若需对单条高价值样本/试剂指定唯一责任人并据此过滤/提醒，当前不支持。

### G3 — 开箱即用的外部数据库同步代理不在仓库内
- **官网描述**：「sync between databases and create automatic uploads into SciNote's Inventory? Use our API」。
- **现状**：Core API v1/v2 已开启，提供库存读写端点；但仓库内不含独立运行的同步守护进程/连接器（如 Ganymede 类集成）。属部署侧能力，非代码缺口。
- **影响**：需自行基于 API 编写同步作业。

### G4 — 移动端 App 不在本仓库
- 官网「ELN Mobile App」为独立交付物，本 Web fork 不含。超出本任务范围，仅作记录。

---

## 四、开发计划（针对缺口与增强）

> 采用垂直切片（vertical slice）方式组织。每项给出：目标、涉及模块、验收口径、优先级。
> 注意：本 fork 已具备所有底层模型与权限骨架，下述计划多为「在既有结构上补齐类型/字段/联动」，风险可控。

### P1（已撤销）— 试剂配方结构化类型
> 见第三节 G1 勘误：官网仅将「recipes」列为可记录的示例信息项，并未描述配方管理功能。本项系对官网的过度解读，予以撤销，不再列入开发计划。

### P2 — 库存条目级「负责人」字段【对应 G2，优先级：低】
- **目标**：在 `RepositoryRow` 增加可选的 `responsible_user_id`（`belongs_to :responsible_user, class_name: 'User', optional: true`），并在条目侧栏、过滤器、到期/低库存提醒的收件人计算中纳入该字段。
- **涉及**：
  - 迁移 + `repository_row.rb` 关联；`RepositoryDatatableService` 增加可过滤列。
  - 权限：`can_manage_repository_rows?` 者可为条目指定负责人。
  - 提醒作业（`RepositoryItemDateReminderJob`/`LowStockNotification`）在负责人存在时额外通知。
- **验收**：为样本 S 指定负责人 U；S 到期/低库存时 U 收到通知；列表可按负责人过滤。
- **注意**：不改动现有团队级权限语义，仅叠加维度。

### P2 — 外部同步连接器示例（基于 Core API）【对应 G3，优先级：低/可选】
- **目标**：提供一个最小可运行的同步作业模板（rake 任务或 Sidekiq worker），演示如何按调度把外部 CSV/数据库经 Core API v1 写入库存，并产出对账报告。
- **涉及**：`lib/tasks/` 新 rake；复用 `repository_import_parser` 解析；调用 `CoreApi` 客户端。
- **验收**：给定示例 CSV，运行后目标仓库新增对应条目且幂等（重复运行不重复建行）。

### P3 — 移动端库存扫码盘点（对应 G4 的轻量替代，优先级：低）
- **目标**：不交付独立 App，而是在 Web 响应式页面增强条码/`barcode_search.js` 的「扫码盘点」流程，使手机浏览器可扫 QR 定位条目并快捷扣减/盘点。
- **涉及**：`barcode_search.js`、库存条目 show 页响应式改造、`repository_stock_value` 快捷扣减入口。
- **验收**：手机浏览器扫描条目 QR → 打开条目页 → 一键记录盘点数量并写 ledger。

---

## 五、建议落地顺序

1. **先确认 G2 是否确属产品需求**：本 fork 当前已满足官网库存页 95%+ 描述，仅剩的「单条目负责人（G2）」属增强型需求。建议先与产品方确认是否进入路线图（官网原句「Assign inventory responsibilities」已由团队级仓库权限 + 设备预约覆盖主要语义）。
2. 若确认：按 **P2（负责人）→ P3（移动端扫码盘点）→ P1（外部同步）** 顺序实施（P1 最独立于核心，可后置）。
3. 每项均以 TDD 红绿切片推进：先写 `spec/models/repository_*` 与 `spec/requests/api/v1/*inventory*` 再实现，保持 `docs/FEATURE_FLAGS.md` 与 `ARCHITECTURE_DECISIONS.md` 同步更新。

---

## 六、关键文件索引（便于接手）

- 仓库核心：`app/models/repository.rb`、`repository_base.rb`、`repository_row.rb`、`repository_cell.rb`、`repository_column.rb`
- 库存：`repository_stock_value.rb`、`repository_stock_consumption_value.rb`、`repository_stock_unit_item.rb`、`repository_ledger_record.rb`、`notifications/low_stock_notification.rb`
- 关系/谱系：`repository_row_connection.rb`、`repository_item_relationships_sidebar.js`
- 设备调度：`equipment_bookings_controller.rb`、`calendar_event.rb`
- 标签打印：`label_printers_controller.rb`、`label_printer.rb`、`fluics_label_template.rb`、`zebra_label_template.rb`
- 序列/质粒：`gene_sequence_assets_controller.rb`、`vue/ove/OpenVectorEditor.vue`
- 导入导出：`utilities/repository_import_parser/importer.rb`、`repository_csv_export.rb`、`repository_xlsx_export.rb`
- 权限：`permissions/repository.rb`
- 开关：`docs/FEATURE_FLAGS.md`（`stock_management_enabled` 等）
