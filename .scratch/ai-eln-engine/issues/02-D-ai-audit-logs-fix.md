# 02-D — ai_audit_logs 修正（独立审计表）

**What to build:** 修正 `ai_audit_logs` 表与 model，使其符合 ADR-0002（独立表、流结束后写完整 response）与 ADR-0004（状态/取消）。现有表缺 `status`、缺多态关联，且 model 无字段声明。需补 `status`、`ai_sessionable` 多态关联、`token_usage`，并移除即时镜像、改为由适配层在流结束后写入。

**Blocked by:** 01 — Engine 骨架与零侵入挂载; 02-A — pgvector 扩展前置; 02-C — ai_interactions 状态机

**Status:** ready-for-agent

- [ ] migration 重写：`ai_eln_ai_audit_logs` 补 `status` 字段（completed/failed/cancelled）
- [ ] 补多态 `ai_sessionable_type`/`ai_sessionable_id` 关联（指向被操作实体）
- [ ] 补 `token_usage` 字段
- [ ] `AiAuditLog` model：声明字段 + 多态关联；移除对 `ai_interaction_id` 的硬依赖（或保留为可选索引）
- [ ] 写入时机改为流结束/重试耗尽后一次性写完整 prompt+response（由 03 适配层调用，非 model 回调）
- [ ] 不写 SciNote 原生 `Activity` 表（符合 ADR-0002）
