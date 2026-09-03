# Issue 跟踪器：本地 Markdown 方案

本仓库的 Issue 和 PRD 以**本地 Markdown 文件**的形式存在，存放在 `docs/agents/issues/` 目录下。
该方案完全离线、无需 `gh` CLI、无需访问 `github.com`，由工程技能直接读写文件来维护。

## 目录结构

```
docs/agents/issues/
├── INDEX.md          ← 全部 Issue 的索引（编号 / 标题 / 标签 / 状态 / 负责人）
├── TEMPLATE.md       ← 新建 Issue 时的空白模板（复制后改名）
├── 0001.md
├── 0002.md
└── …
```

- 每个 Issue 一个文件，文件名即编号：`0001.md`、`0002.md` …（四位零填充，按当前最大编号 +1 递增）。
- Issue 的全部信息（含评论）都在这个文件里，以 **YAML frontmatter + Markdown 正文** 组织。

## Issue 文件格式

```markdown
---
number: 1
title: 示例 Issue 标题
labels: [needs-triage]
status: open            # open | closed
assignee: ""            # 负责人；空字符串表示未认领
blocked_by: []          # 阻塞本 Issue 的编号列表，如 [3, 5]
part_of: ""             # wayfinder 子工单指向的地图编号；否则为空
type: ""                # wayfinder:<type>，如 research / prototype / grilling / task
created: 2026-09-03
---

## 描述
Issue 正文（PRD、背景、验收标准等）。

## 评论
- **@user**（2026-09-03）：第一条评论内容。
- **@user**（2026-09-04）：第二条评论内容。
```

## 约定（本地操作）

- **创建 Issue**：复制 `TEMPLATE.md` 为 `00NN.md`（NN = 当前最大编号 +1），填写 frontmatter 与正文，并在 `INDEX.md` 追加一行。
- **读取 Issue**：直接读取 `00NN.md`；评论在文件底部的「## 评论」一节。
- **列出 Issue**：读取 `INDEX.md`；或用 `search_file` 列出 `docs/agents/issues/*.md` 后按 frontmatter 的 `labels` / `status` 过滤。
- **评论 Issue**：在 `00NN.md` 的「## 评论」一节追加一行 `- **@user**（YYYY-MM-DD）：内容`。
- **应用 / 移除标签**：编辑 `00NN.md` 的 `labels` 数组，并同步更新 `INDEX.md`。
- **关闭**：将 `status` 改为 `closed`，并在 `INDEX.md` 标记；可附一句关闭说明（写入评论或正文）。

## PR 不作为分诊入口

**将 PR 作为请求入口：否。** `/triage` 只处理本地 Issue；外部 PR 不会被拉入分诊队列。

## 当某个技能说「发布到 issue 跟踪器」

在 `docs/agents/issues/` 下新建一个本地 Issue 文件（见上方约定）。

## 当某个技能说「获取相关工单」

读取对应的 `00NN.md` 文件。

## 导航（Wayfinding）操作

供 `/wayfinder` 使用。**地图（map）** 是一个单独的 Issue，其子 Issue 作为工单（ticket）。

- **地图（Map）**：一个带 `wayfinder:map` 标签的 Issue，承载 Notes / Decisions-so-far / Fog 正文。在 frontmatter 写 `labels: [wayfinder:map]`。
- **子工单（Child ticket）**：在子工单 frontmatter 写 `part_of: <地图编号>`。标签用 `wayfinder:<type>`（`research` / `prototype` / `grilling` / `task`）。一旦被认领，在 `assignee` 写入主导开发者。
- **阻塞（Blocking）**：在子工单 frontmatter 的 `blocked_by` 列出阻塞它的 Issue 编号。当 `blocked_by` 中**所有**编号的 Issue 都已 `closed` 时，工单才解除阻塞。
- **前沿查询（Frontier query）**：在 `INDEX.md` 中筛选 `status: open`、且 `blocked_by` 为空（或其中编号全部已 closed）、且 `assignee` 为空的工单；按编号顺序取第一个。
- **认领（Claim）**：将 `assignee` 写为当前开发者 —— 本次会话的首次写入。
- **解决（Resolve）**：在「## 评论」追加结论，将 `status` 改为 `closed`，并在地图 Issue 的 Decisions-so-far 处追加一个上下文指针（相关文件 / 行号 / 链接）。

## 分诊标签

标签字符串沿用 `triage-labels.md` 的定义（`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`）。当某技能提到某个分诊角色时，使用表中对应的标签字符串写入 frontmatter 的 `labels`。

## 环境说明（本地）

本方案**不依赖网络、不依赖 `gh` CLI**，在当前工作区可直接读写文件使用。所有「创建 / 读取 / 评论 / 关闭」操作都是对 `docs/agents/issues/` 下 Markdown 文件的普通读写，由工程技能在本地完成。
