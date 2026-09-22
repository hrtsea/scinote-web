# 07 — 群聊 @ 指派（F6）

**What to build:** 解析企微群 @（`Content` 内 `\u0001@userid\u0001` 标记）+ 指派指令；以组长 context 校验 `can_manage_my_module_users?` 后调指派 service。

**Blocked by:** 06

**Status:** ready-for-agent

- [ ] 群 @ 解析
- [ ] 指派权限校验
- [ ] 调 `ExperimentUserAssignment` / `TaskUserAssignment` service
- [ ] 回执
