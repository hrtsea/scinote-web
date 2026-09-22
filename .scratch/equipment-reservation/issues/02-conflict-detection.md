# 02 — 冲突检测：应用层 validation + 按权限分级（D2.1 / D2.2 / D2.3）

Type: task
Status: ready-for-agent
Blocked by: 01

**What to build:** `validate :no_overlapping_booking`（exclusive 边界，背靠背可衔接），`BLOCKING_STATUSES = %i[reserved confirmed]`（含待审批 reserved）；`attr_accessor :conflict_override` 由控制器按 `can_manage_equipment_bookings?` 设置——普通用户重叠即 `422`，管理员可 `override=true` 放行。

**Checklist**
- [ ] `app/models/calendar_event.rb`：`attr_accessor :conflict_override` + `validate :no_overlapping_booking, if: :equipment_booking?`
- [ ] 独立 exclusive 谓词：`(start_datetime < ? AND end_datetime > ?) OR (start_date < ? AND end_date > ?)`，不复用 `datetime_filter` 的 inclusive `<=/>=`
- [ ] `BLOCKING_STATUSES` 常量；查询按 `(subject_type, subject_id)`（命中 `index_calendar_events_on_subject`）排除自身 `id`
- [ ] 风格对齐 `storage_location_repository_row#ensure_uniq_position`
- [ ] `errors.add(:base, :overlap)` + locale 文案（见 05）
- [ ] 控制器（`#create`/`#update`）：据 `current_user` 权限决定是否设 `conflict_override`；沿用 `rescue RecordInvalid → 422`

**Done when:** 同设备重叠被拦（422）；背靠背通过；reserved 计入冲突；管理员 override 可放行。
