# 02-C — ai_interactions 状态机与字段修正

**What to build:** 修正 `ai_interactions` 表与 model，使其符合 ADR-0004 状态机与 ADR-0002 审计字段。现有 enum `pending/success/failed` 需改为 `queued`→`streaming`→`completed`/`failed`/`cancelled`；补充取消时间戳、token 字段；字段名 `tokens` 统一为 `token_usage`。

**Blocked by:** 01 — Engine 骨架与零侵入挂载; 02-A — pgvector 扩展前置

**Status:** ready-for-agent

- [ ] migration 重写：`ai_eln_ai_interactions` 状态列枚举改为 queued/streaming/completed/failed/cancelled
- [ ] 新增 `cancelled_at` 时间戳字段（用户中途取消留痕）
- [ ] `tokens` → `token_usage`（与 ADR-0002 一致）
- [ ] `AiInteraction` model：enum 改为 `{ queued: 0, streaming: 1, completed: 2, failed: 3, cancelled: 4 }`
- [ ] 移除 `after_commit on: create` 即时镜像审计（改为流结束写，见 02-D）
- [ ] 符合 ADR-0004（状态机）、ADR-0002（token_usage）
