# 02 — AI 数据模型迁移（Engine 内部独立表）

**What to build:** 在 Engine 内通过 migration 创建 4 张独立表，不改动 SciNote 任何原生表结构：`ai_sessions`（多态关联 `ai_sessionable_type`/`ai_sessionable_id`，可挂 Experiment/StepText/ResultText/FormResponse/Table）、`ai_interactions`（状态机 `queued→streaming→completed/failed/cancelled` + token 字段）、`ai_audit_logs`（独立审计，不写原生 Activity）、`ai_embeddings`（pgvector `vector` 类型，经 `enable_extension :vector`）。

**Blocked by:** 01 — Engine 骨架与零侵入挂载

**Status:** ready-for-agent

- [ ] `ai_sessions` 表创建，多态 `ai_sessionable` 关联 + `user_id`，原生表零改动
- [ ] `ai_interactions` 表创建，含 `status` 枚举（queued/streaming/completed/failed/cancelled）、`prompt`、`response`、`model_name`、`token_usage`、取消时间戳
- [ ] `ai_audit_logs` 表创建（user_id/created_at/prompt/response/model_name/token_usage/status/多态关联）
- [ ] `ai_embeddings` 表创建（`vector` 类型列 + pgvector 扩展启用），含指向被索引实体的多态关联
- [ ] migration 在 Engine 内独立运行，不触碰 experiments/notes/recipes/samples 等原生表
- [ ] 符合 ADR-0001（关联策略）、ADR-0002（独立审计）、ADR-0004（状态机）
