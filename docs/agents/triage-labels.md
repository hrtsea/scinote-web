# 分诊标签（Triage Labels）

各技能围绕五个规范化的分诊角色展开论述。本文件将这些角色映射到本仓库 issue 跟踪器中实际使用的标签字符串。

> 本仓库的 issue 跟踪器为**本地 Markdown 方案**（详见 `issue-tracker.md`）：每个 Issue 是一个 `docs/agents/issues/00NN.md` 文件，标签写入其 frontmatter 的 `labels` 数组，并同步到 `INDEX.md`。

| mattpocock/skills 中的标签 | 本地跟踪器中的标签 | 含义                               |
| -------------------------- | ------------------ | ---------------------------------- |
| `needs-triage`             | `needs-triage`     | 维护者需要评估此 Issue             |
| `needs-info`               | `needs-info`       | 等待报告者提供更多信息             |
| `ready-for-agent`          | `ready-for-agent`  | 已完整描述，可供 AFK 智能体处理    |
| `ready-for-human`          | `ready-for-human`  | 需要人工实现                       |
| `wontfix`                  | `wontfix`          | 不会处理                           |

当某个技能提到某个角色时（例如「应用 AFK-ready 分诊标签」），请使用本表中对应的标签字符串，写入目标 Issue 文件的 `labels` frontmatter 数组（并同步 `INDEX.md`）。

右列当前与 mattpocock/skills 完全一致；若你实际使用的词汇不同，请修改右列，并同步所有 `00NN.md` 的 frontmatter 与 `INDEX.md`。
