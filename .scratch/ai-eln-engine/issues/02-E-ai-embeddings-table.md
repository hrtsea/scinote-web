# 02-E — ai_embeddings 表新建（pgvector）

**What to build:** 新建 `ai_embeddings` 表（ADR-0003 混合检索所需），存笔记/附件文本的 embedding 向量。使用 pgvector `vector` 类型，经 02-A 启用的扩展；含指向被索引实体的多态关联 + 文本片段 + 模型名（embedding 后端可双轨）。

**Blocked by:** 01 — Engine 骨架与零侵入挂载; 02-A — pgvector 扩展前置

**Status:** ready-for-agent

- [ ] migration 重写：新建 `ai_eln_ai_embeddings` 表，`embedding` 列类型 `vector`（维度按模型，如 768/1536）
- [ ] 多态 `embeddable_type`/`embeddable_id` 关联（StepText/ResultText/附件文本）
- [ ] `content` 文本片段、`model_name`（embedding 后端标识）
- [ ] 新建 `AiEln::AiEmbedding` model（belongs_to 多态 + vector 列）
- [ ] 建向量索引（如 `ivfflat` 或 `hnsw`）以支持相似召回
- [ ] 符合 ADR-0003（pgvector 语义召回）
