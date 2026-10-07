# 07 — 群聊 @ 指派（F6）

> ⚠️ **本 issue 已被 ADR 0024（2026-09-23）修正（2026-09-24 重组标记）**：F6「派活给组员」语义**不是**实验级角色指派（`ExperimentUserAssignment`）也**不是** `TaskUserAssignment`，而是把组员设为任务（`MyModule`）的**指定成员**——写 `UserMyModule`，权限门 `can_manage_my_module?`，复用 `MyModule#assign_user(user, assigned_by)` 以写入 `designate_user_to_my_module` 活动。
> 此外 addon 当前**无任务概念**（仅有实验级草稿），须先有任务（由 `20`/`21` 建立）才能指派，故本 issue **实际被 `21` 阻塞**。按 ADR 0024 决策选项 A（草稿实验下建/复用主任务）实施。注意 `MyModule#assign_user` 用 `create`（非 `create!`）且 `UserMyModule` 有 uniqueness 校验 → 重复指派会静默失败但仍写 activity，须先判重再调。

**What to build（修正后）:** 解析企微群 @ + 指派指令；校验 `can_manage_my_module?` 后调 `MyModule#assign_user`（先判重）；落点为当前任务（`MyModule`），非实验级 `user_assignments`。

**Blocked by:** 06

**Status:** ready-for-agent

- [ ] 群 @ 解析
- [ ] 指派权限校验
- [ ] 调 `ExperimentUserAssignment` / `TaskUserAssignment` service
- [ ] 回执
