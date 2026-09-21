# 0003 — AI-301 语义检索：混合检索（关键词 + pgvector）

## Status

Accepted (收敛自 V1.1 §10 未决项 1)

## Context

AI-301 要求对实验笔记（StepText / ResultText）、附件文本做**语义**自然语言检索，区别于 SciNote 原生关键词搜索。需确定检索架构与存储/embedding 后端。

架构候选（已 grill）：
- A. 纯 LLM 上下文检索（不建向量库）——大规模语料不准/贵。
- B. 纯向量库——语义强，但放弃原生关键词能力。
- C. 混合检索（原生关键词粗筛 + 向量语义召回互补）——最准。

约束（已查证本地源码）：
- SciNote 已有原生 `tsvector` 全文检索：`tables.data_vector`、`asset_text_data.data_vector`（`tsvector` 类型，基于 `to_tsvector`），由 `searchable_model.rb` / `asset.rb` / `table.rb` 驱动。这是**关键词**索引，非语义。
- SciNote migration 历史已 `enable_extension`（pg_trgm、btree_gist），故 Engine migration 内 `enable_extension :vector` 符合其扩展点哲学，属 DB 配置、非改核心代码，**零侵入成立**。
- 本项目数据库为 PostgreSQL（`config/database.yml`）。

## Decision

采用 **方案 C 混合检索**：

1. **关键词粗筛**：直接复用 SciNote 现有 `tsvector` 检索（调 `SearchableModel` / `asset_text_data` 索引），不改动原生检索代码。
2. **向量语义召回**：Engine 内新建独立表 `ai_embeddings`（`vector` 类型，依赖 pgvector 扩展），存储笔记/附件文本的 embedding；检索时向量召回 top-K。
3. **合并精排**：Engine 业务层对两套结果 merge 去重，送 LLM 做语义精排与重排，返回相似实验条目。
4. **向量存储**：复用现有 PostgreSQL + pgvector 扩展（由 Engine migration `enable_extension :vector` + 建 `ai_embeddings` 表），**不引入独立向量服务**。
5. **embedding 后端**：双轨，由 config 开关切换，机制与 OCR 后端（ADR 同 V1.1 §2.2 AI-102）一致——本地模型（私有化防泄露）/ 公有 API 皆可。

## Consequences

- 语义检索与 SciNote 原生关键词检索互补，不冲突（tsvector 与 pgvector 并列）。
- 零侵入：仅新增 Engine 表 + 一个 DB extension，不碰原生 `data_vector` / 检索逻辑。
- 代价：需 embedding 管线（文本抽取 → embedding → 写 `ai_embeddings`）+ 增量索引（实验/附件变更时同步），复杂度高于方案 A。
- 合规：embedding 双轨默认建议本地，避免配方文本外传；由部署 config 决定。
- 关联 V1.1 §8 后续方向第 1 条（向量数据库）在本 ADR 落地为 pgvector，非独立服务。
