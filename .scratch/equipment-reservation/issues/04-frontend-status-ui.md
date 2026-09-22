# 04 — 前端 Vue：状态徽标 + 取消/审批/覆盖按钮（待定项）

Type: task
Status: ready-for-agent
Blocked by: 01, 02

**What to build:** `app/javascript/vue/equipment_bookings/` 增加状态徽标与操作按钮显隐（按 `can_manage_equipment_bookings?`）：普通用户仅「取消」；管理员额外「审批(reserved→confirmed)」「覆盖(override=true)」。

**Checklist**
- [ ] 状态徽标组件（reserved/confirmed/cancelled/completed 配色）
- [ ] 取消按钮（→ cancelled）
- [ ] 审批按钮（reserved→confirmed，仅管理员）
- [ ] 覆盖确认弹窗（override=true，仅管理员，提交时带留痕见 03）

**Done when:** UI 显示状态且操作按权限显隐。
