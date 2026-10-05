# 0001 — AI-ELN 作为零侵入 Rails Engine Addon

> 本 ADR 已并入原 `docs/ARCHITECTURE_DECISIONS.md` 的 **ADR-014**（AI-ELN 插件以独立 Rails Engine 实现，零侵入；其 LLM 适配层为自有实现，不依赖 ai_protocols），并去重（2026-09-21）。

## Status

Accepted（V1.0 设计基线；ADR-014 承重决策 D1–D4 已并入）

## Context

材料 / 高分子配方研发团队自托管 SciNote 开源版，需在 GLP 实验溯源约束下注入生成式 AI 能力（文档解析、配方提取、实验总结、语义检索），且**不得修改 SciNote 核心源码**。AI 输出仅为辅助参考，原始人工记录保持不可篡改。

约束来源：需求规格 V1.0 §1.2（零侵入 / 权限复用 / 数据隔离 / 可配置后端 / 审计追踪）。

## Decision

AI-ELN 实现为一个独立 Rails Engine（addon 插件），通过 SciNote 官方扩展点注入：

1. **零侵入挂载**：Engine 通过 `initializer` + 路由自注册 + 视图 partial 注入提供能力；不修改 SciNote 的 migrations / 核心模型 / 控制器 / 核心 `config/routes.rb`。引擎按官方 addon 脚手架（`lib/generators/addon`，name=`Scinote::AiEln`）落地于 **`addons/ai_eln/`**，模块命名空间 **`Scinote::AiEln`**（以 `Scinote` 前缀被 `list_all_addons` / Canaid 权限自动收录机制识别）；经根 `Gemfile`（`gem 'scinote_ai_eln', path: 'addons/ai_eln'`）引用装配。路由由 addon 在自身 `engine.rb` 用 `initializer 'scinote_ai_eln.routes' { app.routes.append { mount Engine => '/' } }` 自注册，宿主 `config/routes.rb` 零修改（详见 0005 / 0022 与《Addon 机制综合指南》）。
2. **后台队列**：复用本项目现有的 **Delayed Job**（`delayed_job_active_record`），不引入 Sidekiq（规格 §3 的 Sidekiq 为笔误）。
3. **数据隔离**：AI 会话、调用记录存放于 Engine 内部独立表；AI 生成内容同时保存为实验附件；**绝不覆盖** SciNote 原生业务字段。
4. **大模型后端**：LLM 适配层可配置，支持本地 Ollama 与 OpenAI 兼容 API，可在 `config` 中全局开关。
5. **权限复用**：通过 SciNote 的 **Canaid** 扩展点注册 AI 专用 permission（如 `ai:use`），挂到现有 `user_role`（owner/normal_user/technician/viewer）；`viewer`（只读）不授予 AI 写接口权限，UI 对只读角色隐藏全部 AI 操作按钮。
6. **关联策略**：`ai_sessions` 使用**多态关联**（`ai_sessionable_type` / `ai_sessionable_id`），可挂载到以下真实 SciNote 实体，原生表零改动：
   - `Experiment`（实验，独立模型，✅ 可直接关联）
   - `StepText` / `ResultText`（实验笔记即步骤 / 结果文本子记录）
   - `FormResponse` / `Table`（配方：模板用 Form，实例数据用 Table）
7. **审计日志**：见 0002（零侵入与复用原生 Activity 统一流存在 trade-off，待定）。

### 承重决策补充（源自 ADR-014，已并入）

D1 **独立引擎、并列共存**：新建 `addons/ai_eln`（`Scinote::AiEln::Engine`，`isolate_namespace`），与 `ai_protocols` 并列，不合并、不替代。ai_eln 的 LLM 接入由自有的 `Scinote::AiEln::LlmAdapter` 承担（Ollama/OpenAI 兼容双后端，读 `Scinote::AiEln.configuration`），**不引用** `ai_protocols` 的 `LlmClient`；两者是各自独立挂载、互不耦合的姊妹 addon（易逆转，不当作铁律冲突）。

D2 **地基优先**：首个垂直切片做引擎骨架（自注册路由 + `append_migrations` + `can_use_ai_eln?` 权限 + `LlmAdapter` + `AuditLogger` + 三表 `ai_eln_ai_sessions/interactions/audit_logs` + 侧边抽屉外壳 + 全局开关），后续 25 功能挂其上。

D3 **配置用 ENV + ApplicationSettings 特性开关**：`ai_eln_enabled`（DB `ApplicationSettings#values`，由新建独立迁移置 `true`）+ `AI_ELN_PARSER`（ENV）双判定；**不引入 YAML 配置**。沿用 ai_protocols 已验证范式，可热切换、关 AI 不改代码。注：通用「addon 配置自声明」机制见 0020，本 addon 暂不强制改用 `AddonSetting`。

D4 **引擎自有表走 `append_migrations`**：三表迁移置于 `addons/ai_eln/db/migrate`，经脚手架 `append_migrations` initializer 追加进 host 迁移路径，**宿主 `db/migrate` 零改动**。esignatures 那次直接塞宿主 `db/migrate` 属特例（见 0014），不沿用。

## 合规约束（贯穿全部切片）

AI 输出一律 **HITL**——预览 + 显式确认，禁止自动写 host 原始记录；每次调用落 `ai_audit_logs`；关闭开关后整体退化为原生 SciNote。

## SciNote 模型事实（已查证本地源码）

- `app/models/experiment.rb`：`Experiment` 独立模型，关联 `project`、`my_modules`。
- `app/models/step_text.rb` / `result_text.rb`：实验笔记为 step / result 的子记录，非顶层实体。
- 无 `Note` 模型、无 `Recipe` 模型；配方对应 `Form`/`Table` + `Repository`。
- `app/models/activity.rb`：`Activity` 是普通 `ApplicationRecord`，多态 `subject`，受 `Extends::ACTIVITY_SUBJECT_TYPES` / `ACTIVITY_TYPES` 白名单约束，无官方封装创建入口。
- `Gemfile:100`：权限用 `canaid` gem，角色为 `user_role` 上的 owner/normal_user/technician/viewer。

## Consequences

- Engine 完全可独立启停；关闭后系统退化为原生 SciNote，原生数据不受影响。
- 规格 §4 的 `note_id` / `recipe_id` 字段改为多态关联，避免虚构不存在的外键。
- 升级 SciNote 时只要官方 addon 扩展点稳定，Engine 不受影响；避免猴子补丁核心模型。
- **影响 / 风险**：ai_eln 与 ai_protocols 的 LLM 客户端为共享耦合，若未来禁用 ai_protocols 需同步处理（易逆转）；AI-102 OCR 引擎、P12/P13 语义检索 v1 形态、审计迁移命名等仍有待确认项（见 `docs/开发计划/ai-eln/实现现状与开发计划.md` §10）。向量数据库（spec §8.1）明确推迟。

## 关联

- 0002（AI 审计日志）、0003（语义检索）、0004（LLM 适配层）
- 0005（addon 注册约定）、0022（addon 路由自注册统一策略）
- 0013（ai_protocols：姊妹 addon，各自独立 LLM 客户端）、0020（addon 配置自声明）
- `docs/开发计划/ai-eln/CONTEXT.md`、`docs/开发计划/ai-eln/实现现状与开发计划.md`、`docs/development/addon-dev-workflow.md`
