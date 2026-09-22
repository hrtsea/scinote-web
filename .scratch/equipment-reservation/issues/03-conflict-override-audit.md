# 03 — 冲突覆盖审计留痕（D2.1 审计要求）

Type: task
Status: ready-for-agent
Blocked by: 02

**What to build:** 管理员强制覆盖双写时写一条 `Activity`，记录操作者、被覆盖的冲突预约、时间，满足 GLP 溯源。**严禁无权限路径静默跳过校验。**

**Checklist**
- [ ] 确定 `Activity` 类型（复用 `calendar_event_*` 或新增 override 类型），受 `Extends::ACTIVITY_TYPES` 约束
- [ ] 覆盖路径在 `conflict_override=true` 保存成功后创建 Activity（含被覆盖预约 id）
- [ ] 测试：覆盖写审计；非权限覆盖不产生审计且不绕过校验

**Done when:** 每次管理员 override 留痕；普通用户无法绕过校验。
