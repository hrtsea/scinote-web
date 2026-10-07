# ADR 索引（主题分组）

> **存放约定**：所有 ADR 仍为**单一平铺**于 `docs/adr/`（`NNNN-slug.md`），本文件只是**导航索引**，不移动任何文件、不改文件名。依据 `docs/agents/domain.md` 与 `docs/开发计划/wechat-gateway/CONTEXT.md`：ADR 单一存放于 `docs/adr/`，新决策一律写入此处，不再建并行 ADR 体系。
>
> 分组与 `docs/开发计划/` 的目录结构一一对应，便于"按子系统找决策"。

---

## A. AI-ELN 引擎 / 配方优化（↔ `开发计划/ai-eln`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0001 | `0001-ai-eln-engine-architecture.md` | AI-ELN Rails Engine 总体架构 |
| 0002 | `0002-ai-audit-logging.md` | AI 操作审计日志 |
| 0003 | `0003-ai-semantic-search-hybrid.md` | AI 混合语义搜索 |
| 0004 | `0004-llm-adapter-layer.md` | LLM 适配器层（Ollama + OpenAI 兼容） |
| 0006 | `0006-formulation-first-class-entity.md` | Formulation 一等实体（配方/组分/属性） |
| 0013 | `0013-ai-protocols-addon.md` | AI Protocols addon |
| 0021 | `0021-bayesian-formulation-optimization.md` | 贝叶斯配方优化 |

## B. 平台核心领域（跨目录基础决策）

| ADR | 文件 | 主题 |
|---|---|---|
| 0007 | `0007-equipment-booking-state-machine.md` | 设备预约状态机 ⚠️ 已被 **0023** 取代（SciNote 无 `EquipmentBooking` 模型，实为 `CalendarEvent`） |
| 0008 | `0008-repository-pattern-core-domain.md` | 核心领域仓库模式 |
| 0009 | `0009-protocol-external-import.md` | 协议外部导入 |
| 0010 | `0010-centralized-permission-model.md` | 集中式权限模型 |
| 0033 | `0033-access-control-refactor-write-side-only.md` | access_control 重构：读写分离，判定权归还宿主（**延伸** 0010） |
| 0011 | `0011-serializer-driven-api.md` | 序列化器驱动 API |
| 0012 | `0012-async-jobs-export-notify.md` | 异步任务 / 导出 / 通知 |

## C. addon 规范与注册（↔ `开发计划/addons-config`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0005 | `0005-addon-registration-convention.md` | addon 注册约定 |
| 0020 | `0020-addon-config-schema.md` | addon 配置 schema |
| 0022 | `0022-addon-routes-self-registration.md` | addon 路由自注册 |

## D. 官方功能 / addon 评估（↔ `开发计划/官方功能`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0014 | `0014-esignatures-addon.md` | 电子签名 addon 评估 |
| 0015 | `0015-project-insights-addon.md` | Project Insights addon 评估 |
| 0016 | `0016-item-templates-addon.md` | 条目模板 addon 评估 |
| 0017 | `0017-protocol-version-notifier-addon.md` | 协议版本通知 addon 评估 |
| 0018 | `0018-team-management-assessment.md` | 团队管理评估 |
| 0019 | `0019-integrations-api-assessment.md` | 集成 API 评估 |

## E. WeChat 网关（↔ `开发计划/wechat-gateway`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0023 | `0023-wechat-gateway-addon.md` | WeChat 网关 addon 总体（双通道桥接） |
| 0024 | `0024-task-assignment-semantics.md` | 任务指派语义（F6 = `UserMyModule`） |
| 0025 | `0025-wechat-gateway-command-authorization.md` | 指令权限校验（可见性闸门基座） |
| 0026 | `0026-wechat-gateway-team-scope.md` | Team 作用域 |
| 0027 | `0027-wechat-gateway-no-destructive-commands.md` | 无删除指令 |
| 0028 | `0028-wechat-gateway-target-selection.md` | 目标选择（显式 > 上下文 > 引导） |

## F. 资源申请 / 库存（↔ `addons/eln_ui`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0029 | `0029-resource-application-approvers.md` | 资源申请筛选、可见范围与审批人配置 |
| 0030 | `0030-material-application-is-procurement.md` | 材料类申请＝请购单；终审通过 → 到货验收 → 入库 |
| 0031 | `0031-embed-native-inventories-list.md` | 资源台账内嵌原生 Inventories 列表（不新造外壳；含 ERB 脚本顺序硬约束） |
| 0032 | `0032-receipt-verification-photos-configurable-inspector.md` | 到货验收：照片 ＋ 可配置验货人 ＋ 分批验收 ＋ 未验货阻断（修正 0030 的「验货人沿用终审名单」） |
| 0033 | `0033-access-control-refactor-write-side-only.md` | access_control addon 重构目标形态：读写分离，判定权归还宿主（Proposed） |
| 0034 | `0034-vueify-workspace-list.md` | 工作区列表 Vue 化：自建轻量 AG Grid，打包范式对齐 eln_ui / workbench addon（预打包单体 `.js` + Sprockets），数据走 `window.__ELN_TEAMS__`（Accepted） |

---

## 平铺时序清单（编号即身份，supersede 依据编号）

0001 · 0002 · 0003 · 0004 · 0005 · 0006 · 0007 ⚠️(→0023) · 0008 · 0009 · 0010 · 0011 · 0012 · 0013 · 0014 · 0015 · 0016 · 0017 · 0018 · 0019 · 0020 · 0021 · 0022 · 0023 · 0024 · 0025 · 0026 · 0027 · 0028 · 0029 · 0030 · 0031 · 0032 · 0033 · 0034

共 34 篇。新增 ADR 继续顺延编号（`0035-...`），并补一行到对应主题分组与本清单。
