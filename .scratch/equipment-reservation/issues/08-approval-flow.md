# 08 — 审批流配置 + reserved 超时取消（待定项）

Type: task
Status: ready-for-agent
Blocked by: 01

**What to build:** `equipment_booking_requires_approval` 开关（默认关闭=自服务）；`reserved` 审批 SLA / 超时自动取消，缓解槽位饿死。

**Checklist**
- [ ] `ApplicationSettings` 加 `equipment_booking_requires_approval`
- [ ] 控制器：开关开→新预约初始 `reserved`；审批动作 `reserved→confirmed`
- [ ] 超时 Job：N 分钟未批自动 `cancelled`（可选）

**Done when:** 配置可切换自服务/审批；开启时新预约为 reserved 待批。
