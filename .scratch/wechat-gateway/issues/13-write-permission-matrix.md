# 13 — 写动作权限矩阵：追加 / 收尾 / 建任务各配一把闸

**What to build:** 在可见性之上，给三个**写动作**配上各自的权限闸，并产出一份「指令 → 所需权限」对照表，作为后续新增指令的准入检查表。

**Why:** 能读 ≠ 能写。核实发现：追加正文与收尾 currently **零权限校验**；建任务虽由宿主 `CreateMyModuleService` 内含 `can_create_experiment_tasks?`，但它无权限时走 Rollback 分支**返回 `nil`**，addon 侧会对 `nil` 取 `id` 而炸（已知的 nil-deref 隐患）。三者严重程度不同，但都要补齐。

**ADR:** 0025｜**术语表:** 「读权限与写权限」

**Blocked by:** 11

**Status:** ready-for-agent

- [ ] **追加**（`append_note` / 隐式录入）：需实验写权限；无权限 → 友好提示，**不静默丢内容**（提示里要让用户知道这条没写进去）
- [ ] **收尾**（`/done` → `complete_experiment`）：需实验管理权限。它写的是 `done_at`，属**状态变更**，不能当成随手追加
- [ ] **建任务**（`/newtask` → `create_mymodule`）：显式校验创建权限；并**显式处理宿主返回 `nil`**（先判空再取 `id`，当前会 `NoMethodError`）
- [ ] 产出对照表落进 `docs/指令参考.md`：指令 ｜ 动作 ｜ 所需权限 ｜ 无权限时的文案
- [ ] 启用入口提出的「内容绝不丢弃」原则：任何被权限拒绝的录入，都要在回复里原样提示用户去哪补

**验收：** 三类越权写入均返回友好提示且宿主数据未变更；`/newtask` 在宿主 service 返回 `nil` 时不再抛 `NoMethodError`。

## Answer

## Comments
