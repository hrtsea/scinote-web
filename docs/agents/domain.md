# 领域文档（Domain Docs）约定

Engineering skills 探索 codebase 时，应如何消费这个 repo 的 domain documentation。

> 本仓库约定：**ADR 单一存放处为 `docs/adr/`**（编号 `NNNN-slug.md`，如 `0001-ai-eln-engine-architecture.md`）。历史上曾有 `docs/ARCHITECTURE_DECISIONS.md` 聚合式 ADR 日志，其内容已**归并**进 `docs/adr/` 各独立文件；该聚合文件仅作为索引/概览保留，新 ADR 一律写入 `docs/adr/`，**不要**再退回聚合文件或新建并行 ADR 体系。

## 探索前，先读这些

- 与当前话题相关的 **术语表 `CONTEXT.md`**。本仓库按功能分目录存放，例如 `docs/开发计划/ai-eln/CONTEXT.md`（AI-ELN 插件术语）；不要假设术语表一定在 repo 根。
- **`docs/adr/`** — 读取与你即将处理区域相关的 ADR。按编号或 slug 定位（如 addon 类看 `0005-addon-registration-convention.md`、AI-ELN 看 `0001`~`0007`）。

如果某个文件不存在，**静默继续**。不要标记缺失；不要提前建议创建。`/domain-modeling` skill（经由 `/grill-with-docs` 和 `/improve-codebase-architecture` 调用）会在 terms 或 decisions 实际被解决时懒创建它们。

## 文件结构（本仓库实际形态）

```
/
├── docs/
│   ├── adr/                         ← ADR 单一存放处（NNNN-slug.md）
│   │   ├── 0001-ai-eln-engine-architecture.md
│   │   ├── 0005-addon-registration-convention.md
│   │   └── …
│   ├── 开发计划/
│   │   └── ai-eln/                  ← 功能目录：实现计划 + 术语表
│   │   │   ├── 实现现状与开发计划.md
│   │   │   └── CONTEXT.md
│   └── ARCHITECTURE_DECISIONS.md    ← 聚合式 ADR 日志（已归并，仅留作索引）
└── addons/<name>/                   ← 各 addon 源码（独立 Rails Engine）
```

## 使用术语表的词汇

当你的输出命名某个 domain concept 时（issue title、refactor proposal、hypothesis、test name），使用对应 `CONTEXT.md` 中定义的 term。不要漂移到 glossary 明确避免的 synonyms。

如果你需要的概念还不在 glossary 中，这是一个信号：要么你正在发明项目没有使用的语言（重新考虑），要么确实存在缺口（为 `/domain-modeling` 记录）。

## 标注 ADR 冲突

如果你的输出与现有 ADR 矛盾，明确指出，而不是静默覆盖：

> _Contradicts ADR-0005 (addon 注册约定) — but worth reopening because…_
