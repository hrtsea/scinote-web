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

> ⚠️ 本文件的 ADR 明细已于 **2026-09-21 归并到 `docs/adr/`**（独立 `NNNN-slug.md` 文件）。下方为索引；详细决策请读对应文件。聚合式明细不再在此维护，避免双源失真。

| 原 ADR | 归并目标 (`docs/adr/`) | 主题 |
|--------|------------------------|------|
| ADR-001 | `0008-repository-pattern-core-domain.md` | Repository 自定义表模式是核心领域模型 |
| ADR-002 | `0009-protocol-external-import.md` | 协议从外部源导入（Protocols.io） |
| ADR-003 | `0010-centralized-permission-model.md` | 权限模型为「角色 + 用户分配」集中式设计 |
| ADR-004 | `0011-serializer-driven-api.md` | 序列化器驱动 API 与导出输出 |
| ADR-005 | `0012-async-jobs-export-notify.md` | 导出 / 通知 / 提醒使用异步作业 |
| ADR-006 | `0013-ai-protocols-addon.md` | AI 协议生成以 addon 形式实现（ai_protocols） |
| ADR-007 | `0014-esignatures-addon.md` | 21 CFR Part 11 电子签名以 addon 实现（esignatures） |
| ADR-008 | `0015-project-insights-addon.md` | Project Insights 以 addon 实现（project_insights） |
| ADR-009 | `0016-item-templates-addon.md` | SciNote Templates 现状 + Item Templates addon |
| ADR-010 | `0017-protocol-version-notifier-addon.md` | 协议库版本变更通知 addon |
| ADR-011 | `0018-team-management-assessment.md` | Team Management 现状评估 |
| ADR-012 | `0019-integrations-api-assessment.md` | Integrations & API 现状评估 |
| ADR-013 | `0020-addon-config-schema.md` | Addon 配置自声明机制 |
| ADR-014 | `0001-ai-eln-engine-architecture.md` | AI-ELN 插件以独立 Engine 实现（已并入 0001，去重） |
| ADR-015 | `0021-bayesian-formulation-optimization.md` | 贝叶斯配方优化（AI-501） |
| ADR-016 | `0022-addon-routes-self-registration.md` | Addon 路由自注册统一策略 |

### AI-ELN 子决策（独立于原聚合文件，引擎架构的细化）

| 编号 | 文件 | 主题 |
|------|------|------|
| 0001 | `0001-ai-eln-engine-architecture.md` | AI-ELN 作为零侵入 Rails Engine Addon（含承重决策 D1–D4） |
| 0002 | `0002-ai-audit-logging.md` | AI 调用审计日志：独立 Engine 表 `ai_audit_logs` |
| 0003 | `0003-ai-semantic-search-hybrid.md` | 语义检索：混合检索策略 |
| 0004 | `0004-llm-adapter-layer.md` | LLM 适配层：异步流式 + 可配置重试 |
| 0005 | `0005-addon-registration-convention.md` | Addon 注册约定 |
| 0006 | `0006-formulation-first-class-entity.md` | 配方作为一等实体 |
| 0007 | `0007-equipment-booking-state-machine.md` | 设备预约状态机 |

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
