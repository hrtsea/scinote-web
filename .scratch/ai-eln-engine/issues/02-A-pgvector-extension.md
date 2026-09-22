# 02-A — pgvector 扩展前置（Engine migration 内启用）

**What to build:** 在 AI-ELN Engine 的 migration（`engines/ai_eln/db/migrate/20260902000001_create_ai_eln_tables.rb`，重写）中启用 PostgreSQL `vector` 扩展，为 `ai_embeddings` 表提供向量类型支持。SciNote 已有 `enable_extension` 先例（pg_trgm/btree_gist），此属 DB 配置、非改核心代码，零侵入成立（ADR-0003）。

**Blocked by:** 01 — Engine 骨架与零侵入挂载

**Status:** ready-for-agent

- [ ] migration 内含 `enable_extension :vector`（已存在迁移重写时加入）
- [ ] 验证目标 PG 已安装 pgvector 包（否则 migrate 失败，需运维装扩展）
- [ ] 不修改 SciNote 原生迁移或扩展列表
- [ ] 符合 ADR-0003（向量存储 = pgvector）

> 注：因未部署，本项与 02-B/02-C/02-D/02-E 合并在**同一次迁移重写**内完成（用户决策：重写原迁移）。
