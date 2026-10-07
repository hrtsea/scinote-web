# 09 — 设备预约（F10）

> ⚠️ **本 issue 描述已过时（2026-09-24 重组标记，见 ADR 0023 §实现进度）**：SciNote **无 `EquipmentBooking` 模型**。设备预约在宿主实为 `CalendarEvent`（`equipment_booking` 类），`scinote_service_writer#book_equipment` 已按 `CalendarEvent` 实现。本 issue 仅须把"模型名"更正为 `CalendarEvent`，其余待办不变。

**What to build（修正后）:** addon 内直用 `CalendarEvent`（`equipment_booking` 类，非 `EquipmentBooking` 模型）封装设备预约：冲突校验 + 回执。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] `EquipmentBooking.create!` 封装（user / equipment / start / end）
- [ ] 冲突校验
- [ ] 回执
