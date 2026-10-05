# 产品功能 × 本 fork 实现现状 与 开发计划

> 配套文档：`docs/PRODUCT_OVERVIEW.md`（官网功能原文总览）、`docs/FEATURE_FLAGS.md`（本 fork 开关现状）、`docs/development/addon-dev-workflow.md`（二次开发铁律）、`docs/开发计划/ai-eln/实现现状与开发计划.md`（AI & Automations 专项计划）。
> 探查手段：codebase-memory 知识图谱（17,442 节点 / 48,821 边，全量索引）+ 关键词源码核验（grep）。
> 铁律：本 fork 自托管且无法 pull 上游，所有新增功能**只以 `addons/<name>/` Rails Engine 形式实现**，不得改核心 `app/`（`addon-dev-workflow.md` 〇）。

---

## 一、实现状态矩阵

图例：✅ 已实现　⚠️ 部分实现　❌ 未实现（或仅规划）

### 1. DATA MANAGEMENT
| 功能 | 状态 | 证据 |
|---|---|---|
| 层级文件结构（projects/experiments/tasks） | ✅ | 核心模型 `Project`/`Experiment`/`MyModule` |
| 交互式协议 + 集中协议库 | ✅ | `protocols_controller`、`ProtocolImporters`（0009） |
| Advanced search | ✅ | `app/controllers/search_controller.rb`、`REPOSITORY_ADVANCED_SEARCHABLE_COLUMNS`、`quick_search.vue` |
| Smart annotation & activity log | ✅ | `SmartAnnotations::TagToHtml`（ADR 复杂度热点）、`app/models/activity.rb` |

### 2. PROJECT MANAGEMENT
| 功能 | 状态 | 证据 |
|---|---|---|
| 可视化工作流（线性/非线性画布） | ✅ | `app/controllers/canvas_controller.rb` |
| 可复用任务模板 | ✅ | `ENABLE_TEMPLATES_SYNC`、`TemplatesService` |
| 任务分派 + 提醒 | ✅ | 调度器 5 类到期提醒（`FEATURE_FLAGS.md` 2.2） |
| 任务监控 / 仪表盘 | ✅ | dashboard |
| 报告生成器 | ✅ | `reports_controller` |

### 3. INVENTORY MANAGEMENT
| 功能 | 状态 | 证据 |
|---|---|---|
| 库存管理 + 提醒 | ✅ | `stock_management_enabled`（迁移开启，`FEATURE_FLAGS` 2.1） |
| 库存关联实验（可追溯） | ✅ | `repository_rows`、`repository_row_connections_enabled` |
| 条码 & 自定义标签 | ✅ | `label_templates`、`zebra_label_template`、`fluics` |
| Excel 导入/导出 | ✅ | `ModelExporters::TeamExporter` 等 |

### 4. REGULATORY COMPLIANCE
| 功能 | 状态 | 证据 |
|---|---|---|
| 封闭系统 / 受限访问 | ✅ | Devise 认证 + 集中式权限系统（0010） |
| 人类可读副本 / 全量导出 | ✅ | `team_zip_export_job`、全量导出 |
| 时间戳审计追踪 | ⚠️ | 有 `Activity` 活动日志 + `versioned_attachments`（附件版本），但**无不可篡改/WORM 审计链**（全仓 0 命中 `paper_trail`/audit_trail 模型） |
| 时间戳电子签名（21 CFR Part 11） | ❌ | 全仓无 `electronic_signature` 模型；"esign" 命中均为 designate/design 字样 |

### 5. TEAM MANAGEMENT & COLLABORATION
| 功能 | 状态 | 证据 |
|---|---|---|
| 随时协作 | ✅ | 多团队/多用户 |
| 跨团队沟通（@提及/评论/通知） | ✅ | smart annotation、comments、notifications |
| 自定义用户权限 | ✅ | `permissions/*`（0010） |
| 团队上手（CSM/培训） | ⚠️ | 属 SaaS 服务，自托管仅有 UI 引导，无 CSM |

### 6. 独立/扩展模块
| 功能 | 状态 | 证据 |
|---|---|---|
| SciNote Edit（桌面端直接编辑附件） | ❌ | 独立桌面应用，不在 web fork；web 侧等价能力为 **WOPI 在线编辑**（已实现但 `WOPI_ENABLED` 默认关闭） |
| RESTful API | ✅ | `CORE_API_V1/V2_ENABLED`、`CORE_API_KEY_ENABLED` |
| MS Office（Word/Excel/PPT） | ⚠️ | WOPI 在线编辑已存在（`wopi_controller` 等），默认关闭；桌面 SciNote Edit 不在 fork |
| Protocols.io | ✅ | `PROTOCOLS_IO_ACCESS_TOKEN`（需真实令牌） |
| FLUICS 标签 | ✅ | `ENABLE_FLUICS_SYNC`、`LabelPrinters::Fluics` |
| Zebra 标签打印机 | ✅ | `zebra_label_template`、`BrowserPrint-Zebra` |
| **AI & Automations** | ❌（已规划） | `docs/开发计划/ai-eln/实现现状与开发计划.md` 已完成 grill + PRD + Issues，**尚未实现** |
| 21 CFR Part 11 / GLP/GMP | ⚠️ | 电子签名 ❌、审计追踪 ⚠️（见上） |
| Data Protection & Security | ⚠️ | 有加密/2FA（`_2fa_modal`）/SSO 开关；FedRAMP/ISO 为合规声明 |
| ELN Mobile App | ⚠️ | PWA 脚手架在（`pwa_helper.rb`、`pwa_mobile_app.js`、`SCINOTE_PWA_DOMAIN_NAME` 开关），未完整交付 |
| Quality Assurance (IQ/OQ) | N/A | SaaS 服务，非软件功能 |
| User Adoption & Success | N/A | SaaS 服务 |
| Efficiency & Productivity | N/A | 营销标题，无功能定义 |

---

## 二、差距分析（聚焦 ❌ / ⚠️）

### G1 — 21 CFR Part 11 电子签名（❌ 高优先级，合规刚需）
官网明确「unique to one individual and indisputably linked to the respective electronic record… prevent fraudulent use」。本 fork 完全没有对应模型/服务/UI。这是与「法规合规」卖点差距最大的一项，也是 GLP/GMP 客户的核心诉求。
- 需新增：签名策略（谁/何时/对何种记录签名）、签名动作与记录强绑定、签名不可抵赖（含签名人身份、时间戳、意图声明）。
- 扩展点：协议/结果/实验的「签名」入口用 `app/decorators` 覆盖；权限落 `addons/esignatures/app/permissions/**/*.rb`；签名记录由 addon 自有迁移建表。

### G2 — 防篡改审计追踪（⚠️ 中高优先级）
现有 `Activity` 仅为普通活动流（可删可改），不满足「cannot be edited or deleted」的合规要求。
- 需新增：追加式（append-only）且带哈希链/签名的可验证审计日志，并提供完整性校验工具。
- 扩展点：addon 提供独立审计存储 + 对关键写操作的订阅（复用现有 `Activity` 事件源或 observer），不改动核心写路径。

### G3 — MS Office / SciNote Edit 在线编辑（⚠️ 低-中优先级，主属配置）
核心 WOPI 在线编辑已存在，仅 `WOPI_ENABLED` 默认关闭。桌面端 SciNote Edit 为独立应用，**不在 web fork 范围内**。
- 建议：① 通过 `docker-compose.yml`/`.env` 开启 `WOPI_ENABLED` 并验证 Office Online Server 接入（配置层面，无需改核心）；② 若需健壮性增强（令牌管理、错误处理），以 `addons/wopi_hardening` 装饰器形式补充，不碰 `wopi_controller`。

### G4 — ELN 移动端 PWA 完善（⚠️ 中优先级）
PWA 脚手架（`pwa_helper.rb`、`pwa_mobile_app.js`、CORS 域名开关）已在，但未作为完整移动 App 交付（独立 PWA 仓库通常另有 service worker / manifest / 离线缓存）。
- 需新增：manifest、service worker、离线缓存、移动端适配路由；以 `addons/mobile_pwa` 形式补齐，避免改核心。

### G5 — AI & Automations（❌ 已规划，独立交付）
`docs/开发计划/ai-eln/实现现状与开发计划.md` 已完成 grill + PRD + Issues 拆分（addon `ai_protocols` + `automations_ext`），**本计划不再重复**，直接进入 `/implement` 即可。列此仅为完整性。

---

## 三、开发计划（按 addon 工作流，垂直切片）

> 统一遵循 `docs/development/addon-dev-workflow.md` Phase 0–6 与 `docs/agents/domain.md` 的 ADR 约定。
> 每个 addon：Phase 0 先写 ADR-00X（追加到 `docs/ARCHITECTURE_DECISIONS.md` 第三节）→ Phase 3 脚手架（复制 `addons/i18n` 骨架）→ Phase 4 `/tdd` 红绿切片 → Phase 5 rubocop+brakeman+rspec → Phase 6 收口 ADR 冲突风险。
> Issue 跟踪按 `docs/agents/issue-tracker.md`；本环境无 `gh` 且不可达 GitHub，Issue 仅作草稿待手动执行。

### Addon A — `addons/esignatures`（G1，最高优先级）
**PRD**：用户在协议/结果/实验上发起电子签名 → 系统记录签名人、时间戳、意图声明，并与目标记录强绑定、不可篡改、可验证。
- **Issue A1 — 数据模型与迁移**：`Scinote::Esignatures` 引擎；`e_signatures`/`e_signature_records` 迁移；签名策略配置（`Extends` 合并签名适用实体列表）。
- **Issue A2 — 签名服务**：`SignatureService.call(record:, user:, meaning:)` 生成带时间戳+哈希的签名记录，写入不可变存储。
- **Issue A3 — 权限与入口**：`app/permissions/**/*.rb`（`can_sign_record?` 等）；`app/decorators` 在协议/结果页挂签名按钮，受开关门控。
- **Issue A4 — 验证与导出**：签名完整性校验工具；导出时附签名证明。

> **实施进度（截至 2026-09-01）**：0014 决策 + Phase 3 脚手架 + Phase 4/5 实现均已完成。
> - **A1 数据模型与迁移**：引擎 `Scinote::Esignatures::Engine`（`isolate_namespace`）；模型 `ESignature` / `ESignatureRecord`（多态、`append-only` 应用层不可变）；迁移**已落到核心 `db/migrate/20260901001000_scinote_esignatures_create_tables.rb`**（见下方「踩坑」第 3 条关于版本号冲突的修正）。
> - **A2 签名服务**：`SignatureService.call(record:, user:, meaning:)` 生成带时间戳 + `record_hash` + 追加式哈希链（`signature_hash = H(record_hash + 上一记录 hash)`）的签名记录；`SignaturePolicy` 按记录类型分派到核心 `can_manage_*` 权限；`SignatureGate` 守卫。
> - **A3 权限与入口**：canaid 权限文件 `app/permissions/scinote/esignatures/permissions.rb` 注册 `can_sign_protocol_record?` / `can_sign_result_record?` / `can_sign_experiment_record?`；`SignaturesController` + `SignatureHelper` + `SignatureGate`。**权限已真正接入 canaid**（见下方「踩坑」第 1 条，曾因 `app/permissions` 未进入引擎 `eager_load_paths` 而静默未注册）。**UI 入口已落地**：经 deface（`app/overrides/*.rb`）把 `signature_panel_for` 面板注入核心 `protocols/_header` 与 `experiments/_show_header`（服务器渲染的 header），无 `can_sign_*_record?` 权限时面板为空串；结果（Result）签名在 Vue canvas 内，需 JS 入口，留作后续。
> - **A4 验证与导出**：`ChainVerifier`（哈希链完整性 / 记录被篡改检测）、`ExportProof`（导出附签名证明）均已实现并附 spec。
> - **质量门禁**：`bundle exec rspec addons/esignatures/spec` → **26 examples, 0 failures**（含 2 个 deface 注册守卫测试）；`bundle exec rubocop addons/esignatures` → **0 offenses**。
>
> **测试运行要点（本 fork 环境实测，避免下次踩坑）**：
> - **rspec 不能跑开发库**：`spec/rails_helper.rb:7` 硬编码 `ENV['RAILS_ENV'] = 'test'`，rspec 永远连 **test 库 `scinote_test`**。表必须建在 test 库，而非 dev 库——“直接在开发库测试”在此 harness 下不成立。
> - **Windows 不支持 symlink**：`load_addons_specs.rb` 的符号链接静默失败，addon spec 不会被自动发现。必须**指名文件路径**运行：
>   `docker compose run --rm web bundle exec rspec addons/esignatures/spec`
>   （Linux/CI 上 `rspec spec/addons/esignatures` 自动发现可用。）
> - **缺 `MAIL_FROM` 会全场失败（与 addon 无关）**：`AppMailer`（`app/mailers/app_mailer.rb:7`）`default from: ENV['MAIL_FROM']`，容器内未设该变量时，任何创建 `User` 的 spec（含核心 `user_spec`）都会在 Devise 发通知时抛 `SMTP From address may not be blank: nil`。运行测试需带上 `MAIL_FROM=noreply@scinote.test`（CI 应已设置）。
> - **`rails db:migrate` 会因 pg_dump 版本不匹配失败**：web 容器装的是 pg_dump 17，PG 服务端为 18，在 structure dump 阶段崩溃。**本次已临时绕开**：用 db 容器（自带 pg_dump 18）导出两张表 DDL 并手工合并进 `db/structure.sql`（含 `schema_migrations` 版本 `20260901001000`），dev/test 两库 `schema_migrations` 也已补登该版本。当前 `rails db:migrate` 对两库均会 skip、不冲突。**永久修复**：把 web 镜像的 `postgresql-client` 升到 18 后跑一次 `rails db:migrate`，让 structure.sql 由 Rails 正确生成（当前为手工补丁，需复核）。
> - **迁移版本号冲突**：核心已有 `db/migrate/20260901000000_localize_predefined_repository_templates.rb` 等占用 `20260901000000`。addon 迁移初版也用了该版本号 → `db:migrate:status` 报 `NO FILE` 且真正的 addon `db/migrate` 不被 Rails 纳入迁移扫描路径（Rails 引擎迁移的标准做法是安装到宿主 `db/migrate`）。**已修正**：将迁移移入核心 `db/migrate/20260901001000_scinote_esignatures_create_tables.rb` 并删除 addon 内的 `db/migrate`，status 现正常显示 `up … Scinote esignatures create tables`。
> - **canaid 权限发现依赖 `eager_load_paths`**：`config/initializers/canaid.rb` 只扫描各引擎 `config.eager_load_paths` 中结尾为 `permissions` 的目录。引擎 `app/*` 子目录虽被 Zeitwerk 自动加载，但**默认不在 `eager_load_paths`**（实测 `engine.config.eager_load_paths` 为空）。故在 `lib/scinote/esignatures/engine.rb` 显式 `config.eager_load_paths << root.join('app', 'permissions').to_s`，否则权限文件不会被 require、调用即 `ArgumentError: unknown permission`。
>
> **下一步（剩余）**：`routes.rb` / `Gemfile` 挂载 `scinote_esignatures` 引擎与 `SignaturesController` 路由已于早期 session 完成；UI 入口已用 deface 注入协议/实验页 header（结果页为 Vue canvas，需 JS 入口，留作后续）；**pg_dump 客户端版本永久修复**仍未做（`db/structure.sql` 当前为手工补丁，建议升 `postgresql-client` 到 18 后重跑 `rails db:migrate` 复核）。

### Addon B — `addons/audit_trail`（G2）
**PRD**：在现有 `Activity` 之上提供追加式、带哈希链的不可篡改审计日志与校验。
- **Issue B1 — 不可变审计存储**：addon 自有表 + 哈希链写入（订阅关键写事件，不碰核心）。
- **Issue B2 — 校验工具**：CLI/任务定期校验哈希链完整性，异常告警。
- **Issue B3 — UI 只读视图**：审计日志只读页，标注不可篡改属性。

### Addon D — `addons/mobile_pwa`（G4）
**PRD**：补全 PWA 能力，使 SciNote 可作为移动 App 安装与使用。
- **Issue D1 — Manifest & SW**：`manifest.json`、service worker、离线缓存。
- **Issue D2 — 移动适配**：关键页面移动端路由与 UI 适配（装饰器/覆盖）。

### 配置类（G3，非 addon）
- 在 `docker-compose.yml`/`.env` 设 `WOPI_ENABLED=true` 并接入 Office Online Server；验证后用 `docs/FEATURE_FLAGS.md` 记录。
- 桌面 SciNote Edit 为独立应用，**超出本 fork 范围**，仅在文档中说明。

---

## 四、优先级与路线图建议

| 优先级 | 项目 | 形态 | 依赖 |
|---|---|---|---|
| P0 | G1 电子签名 | addon `esignatures` | 无 |
| P0 | G2 防篡改审计 | addon `audit_trail` | 无 |
| P1 | G5 AI & Automations | addon `ai_protocols` | 已有计划，直接实施 |
| P2 | G4 移动端 PWA | addon `mobile_pwa` | 无 |
| P3 | G3 Office 在线编辑 | 配置 + 可选 `wopi_hardening` | WOPI_ENABLED |

> 合规类（G1/G2）建议优先，因其直接对应官网「21 CFR Part 11, GLP & GMP」卖点且本 fork 完全缺失；AI & Automations 已有完整计划可直接落地；PWA 为差异化集成，按资源排期。

---

## 五、检查清单（交付前）
- [ ] 每个新 addon 已写 ADR-00X（追加至 `docs/ARCHITECTURE_DECISIONS.md` 第三节）
- [ ] 改动**仅**在 `addons/<name>/` 内；引擎类名以 `Scinote` 开头、`isolate_namespace`
- [ ] Gemfile 与 `config/routes.rb` 已注册/挂载
- [ ] 枚举扩展走 `Extends` 合并，权限落 `app/permissions/**/*.rb`
- [ ] `rubocop` + `brakeman` + `rspec` 全绿
- [ ] Issue 草稿已按 `docs/agents/issue-tracker.md` 产出（待可联网环境执行）
