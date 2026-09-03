# 领域文档（Domain Docs）

工程技能在探索代码库时，应如何消费本仓库的领域文档。

## 在探索之前，先读这些

- **仓库根目录的 `CONTEXT.md`** —— 这是一个单上下文（single-context）仓库，因此没有 `CONTEXT-MAP.md`。
- **`docs/ARCHITECTURE_DECISIONS.md`** —— 本仓库的 ADR 日志。请阅读与你要开发领域相关的那些 ADR。

如果上述任何文件不存在，**请静默继续**。不要指出它们缺失，也不要建议预先创建。当术语或决策真正被确定时，`/domain-modeling` 技能（通过 `/grill-with-docs` 和 `/improve-codebase-architecture` 进入）会按需惰性创建这些文件。

## 文件结构

单上下文仓库：

```
/
├── CONTEXT.md
├── docs/
│   └── ARCHITECTURE_DECISIONS.md   ← ADR 日志（ADR-001 … ADR-005）
└── app/
```

## ADR 约定

本仓库将 ADR 集中存放在一个文件 `docs/ARCHITECTURE_DECISIONS.md` 中，位于 **三、关键架构决策（ADR）** 一节，编号为 `ADR-00N`。新 ADR 追加到该文件即可；**不要**另建并行的 `docs/adr/` 目录。

## 使用术语表的词汇

当你的输出要命名某个领域概念时（例如在 issue 标题、重构提案、假设、测试名称中），请使用 `CONTEXT.md` 中定义的术语。不要擅自改用术语表明确规避的同义词。

如果你需要的概念尚未出现在术语表中，这是一个信号 —— 要么你正在发明项目并不使用的语言（请重新考虑），要么确实存在真实空白（请为 `/domain-modeling` 记下这一点）。

## 标记 ADR 冲突

如果你的输出与某个既有 ADR 相矛盾，请显式指出，而不是悄悄地覆盖：

> _与 ADR-001（Repository 自定义表模式是核心领域模型）相矛盾 —— 但值得重新审视，因为……_
