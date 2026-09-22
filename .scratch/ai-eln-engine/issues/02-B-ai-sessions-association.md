# 02-B — ai_sessions 多态关联修正

**What to build:** 修正 `ai_sessions` 表的宿主关联，使其符合 ADR-0001。现有实现用 `host_type`/`host_id` 且注释提及 Recipe/Protocol——需改为标准多态 `ai_sessionable_type`/`ai_sessionable_id`，关联范围限定为 `Experiment` / `StepText` / `ResultText` / `FormResponse` / `Table`（**删除不存在的 Recipe/Protocol 假设**）。同步修正 `AiSession` model。

**Blocked by:** 01 — Engine 骨架与零侵入挂载; 02-A — pgvector 扩展前置

**Status:** ready-for-agent

- [ ] migration 重写：`ai_eln_ai_sessions` 列 `host_type`/`host_id` → `ai_sessionable_type`/`ai_sessionable_id`（或新增标准多态列并移除旧列）
- [ ] 关联范围仅为 Experiment/StepText/ResultText/FormResponse/Table，移除 Recipe/Protocol
- [ ] `AiSession` model：多态 `belongs_to :ai_sessionable, polymorphic: true`
- [ ] 原生表零改动（不反向加外键到 experiments 等）
- [ ] 符合 ADR-0001（关联策略）
