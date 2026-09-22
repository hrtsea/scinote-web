# 08 — 混合语义检索（AI-301~303）

**What to build:** 知识挖掘能力：AI-301 语义自然语言检索（复用 SciNote 原生 `tsvector` 关键词粗筛 + Engine 内 `ai_embeddings` 向量语义召回，merge 后 LLM 精排）、AI-302 相似实验推荐（新建实验时检索本项目历史相似实验，展示条件/失败案例）、AI-303 异常数据提示（对比同批次历史，标记偏离，人工复核）。

**Blocked by:** 02 — AI 数据模型迁移; 03 — LLM 适配层与异步流式管道

**Status:** ready-for-agent

- [ ] embedding 管线：实验笔记(StepText/ResultText)/附件文本抽取→embedding→写 `ai_embeddings`（双轨后端，同 OCR 开关）
- [ ] AI-301 混合检索：原生 tsvector 粗筛 + ai_embeddings 向量召回 → merge → LLM 精排
- [ ] AI-302 相似实验推荐：新建实验时检索本项目历史
- [ ] AI-303 异常数据提示：对比历史标记偏离，人工复核
- [ ] 增量索引：实验/附件变更时同步 `ai_embeddings`
- [ ] 符合 ADR-0003（混合检索）、ADR-0004（管道）
