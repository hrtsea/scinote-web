# Spec — 设备预约状态机与冲突检测

> Status: ready-for-agent
> 来源（已综合，未做新访谈）：`docs/adr/0007-equipment-booking-state-machine.md`、`docs/agents/issue-tracker.md`、`CONTEXT.md`（预约术语表）、`.scratch/equipment-reservation-state-machine-design.md`。
> 领域词汇：预约 / Reservation、设备 / Equipment（`RepositoryRow`）、预约状态 / Reservation Status（`calendar_events.status`）、冲突 / Conflict（双重预订）、时间区间 / Time range、强制覆盖 / override。

## Problem Statement

SciNote 的 Equipment Bookings 存放在 `calendar_events`（`event_type = equipment_booking`，`subject` 指向被预约的 `RepositoryRow`），但**没有生命周期状态，也不阻止同一设备时间重叠的多次预约**。结果：(1) 用户无法表达「待审批 / 已确认 / 已取消 / 已完成」的预约语义；(2) 两名用户可预约同一设备同一时段，造成实验室排程冲突、仪器争用、数据污染风险。需要在不改 SciNote 既有状态机约定的前提下，给预约增加状态机与冲突防护。

## Solution

给 `calendar_events` 增加 `status` 整数枚举（**沿用 Rails 原生 `enum`，不引入 aasm**），以状态机表达预约生命周期；并在模型层新增冲突校验 `validate :no_overlapping_booking`，以 exclusive 边界判定同一 `RepositoryRow` 上「占用中」预约的时间区间相交。**按权限分级**：普通用户重叠即被硬拦截（HTTP 422），具备 `can_manage_equipment_bookings?` 的管理员 / 设备负责人可显式「强制覆盖」放行，且每次覆盖写入 `Activity` 留痕（满足 GLP 溯源）。数据库 `EXCLUDE` 约束作为可选加固，默认降级（与「按权限覆盖」互斥）。

## User Stories

1. As a lab member, I want to book an equipment for a time range, so that I can reserve instrument time for my experiment.
2. As a lab member, I want my new booking to be `confirmed` immediately (self-service default), so that I don't wait for manual approval for routine instruments.
3. As a lab member, I want to see the status of my booking (reserved / confirmed / cancelled / completed), so that I know whether it is active or released.
4. As a lab member, I want to cancel my booking, so that the instrument slot is freed for others.
5. As a lab member, I want a booking to become `completed` after its end time, so that finished reservations no longer occupy the schedule view.
6. As a lab member, I want to be blocked from creating a booking that overlaps an existing `confirmed` booking on the same equipment, so that I don't double-book an instrument.
7. As a lab member, I want to be blocked from creating a booking that overlaps an existing `reserved` (pending-approval) booking, so that a pending request also occupies the slot.
8. As a lab member, I want back-to-back bookings (my booking starts exactly when another ends) to be allowed, so that equipment is used continuously without false conflicts.
9. As a lab member, I want a clear error message when my booking conflicts, so that I understand why it was rejected.
10. As a lab member, I want the conflict check to cover both timed events and all-day events, so that a full-day booking blocks a same-day timed booking.
11. As a lab manager, I want to force-save a booking that overlaps an existing one, so that I can manually resolve scheduling conflicts.
12. As a lab manager, I want every forced override to be recorded in the audit log (who, which conflicting booking, when), so that overrides are traceable for GLP.
13. As a lab manager, I want to approve a `reserved` (pending) booking into `confirmed`, so that shared expensive instruments are gated behind approval.
14. As a lab manager, I want to configure whether bookings require approval (`equipment_booking_requires_approval`), so that routine vs. shared instruments use different policies.
15. As a lab manager, I want cancelled / completed bookings to NOT block new bookings, so that freed slots are reusable.
16. As an admin, I want existing historical bookings to keep working after the change (backfilled to `confirmed`), so that the migration is non-disruptive.
17. As a lab member, I want the calendar UI to show a status badge per booking, so that I can scan active vs. released reservations at a glance.
18. As a lab manager, I want status badges plus cancel / approve / override actions to appear only with appropriate permissions, so that users only see actions they may take.
19. As a system, I want the conflict validation to skip recurrence expansion (only the base event is checked), so that we accept a known limitation for repeating series.
20. As a system, I want the reminder job (24h) to fire only for `confirmed` bookings, so that cancelled / reserved don't spam reminders.
21. As a compliance officer, I want a database-level atomic guarantee option (EXCLUDE) available for deployments that forbid overrides, so that high-stakes environments can trade flexibility for atomicity.

## Implementation Decisions

- **不引入 aasm**：全库无此 gem；状态用 Rails 原生 `enum status:` + 手写 `validate :check_status_transition`，对齐 `my_module_status` / `label_printer` / `form_response` 既有约定。
- **Schema 变更**：`calendar_events` 新增 `status` 整数列，`default: 1`（`confirmed`），`null: false`；迁移同时把存量 `event_type = equipment_booking AND status IS NULL` 行回填为 `confirmed`（否则 `where(status: BLOCKING_STATUSES)` 不匹配 nil，冲突检测失效）。
- **状态机（来自 ADR-0007 D1，prototype 精确编码）**：

  ```ruby
  # app/models/calendar_event.rb
  enum status: { reserved: 0, confirmed: 1, cancelled: 2, completed: 3 }
  # 跃迁矩阵（✓ 合法）：
  #   reserved  -> confirmed | cancelled
  #   confirmed -> cancelled  | completed
  #   cancelled / completed 为终态
  # 初始 status 为 nil（新建未置）跳过跃迁校验，由 before_validation / 控制器设默认。
  ```

- **冲突检测（来自 ADR-0007 D2，prototype 精确编码）**：

  ```ruby
  attr_accessor :conflict_override
  BLOCKING_STATUSES = %i[reserved confirmed]   # 占用中（含待审批 reserved）
  validate :no_overlapping_booking, if: :equipment_booking?
  # no_overlapping_booking: return if conflict_override
  #   同 (subject_type, subject_id) 且 status IN BLOCKING_STATUSES 且排除自身(id)
  #   exclusive 边界: (start_datetime < other.end AND end_datetime > other.start)
  #                  OR (start_date < other.end AND end_date > other.start)
  #   命中则 errors.add(:base, :overlap)
  ```

- **分级拦截锚点**：`app/permissions/repository.rb` 的 `can_manage_equipment_bookings?`（受 `equipment_booking_enabled?` 门控）。控制器据 `current_user` 权限决定是否把 `conflict_override = true` 传入模型；无权限路径绝不跳过校验。
- **控制器复用现有出口**：`CalendarEventsController#create/#update` 已在事务内 `create!`/`update!` 并 `rescue ActiveRecord::RecordInvalid → 422`，新增 validation 自动生效；仅需 `permit` 新增 `status` 与 `override` 参数，并在保存前据权限设置 `conflict_override`。
- **覆盖留痕**：强制覆盖保存成功后写一条 `Activity`（复用 `calendar_event_*` 类型或新增 override 类型），记录操作者、被覆盖预约 id、时间。**严禁无权限路径静默跳过校验**。
- **EXCLUDE 约束（D2.5）降级**：默认不采用；仅当某部署禁用覆盖且要求原子性时启用，并与 D2.1 覆盖能力二选一、互斥。
- **审批流为配置项（非决策反转）**：新增 `equipment_booking_requires_approval`（沿用 `ApplicationSettings['equipment_booking_enabled']` 机制）；关闭=自服务（创建即 `confirmed`），开启=创建 `reserved` 由管理员 approve。

## Testing Decisions

- **只测外部行为，不测实现细节**：对 validation 的测试通过「保存后是否报错 / 是否 422」断言，不依赖私有方法名。
- **Seams（优先复用现有、最高层）**：
  1. **请求层 seam（最高层、首选）**：`CalendarEventsController#create` / `#update` 的 RSpec request spec —— 断言普通用户重叠返回 `422`、管理员带 `override` 成功且生成 `Activity`、背靠背返回 `2xx`。控制器已 `rescue RecordInvalid → 422`，无需改动即可作为 seam。
  2. **模型层 seam（单元）**：`CalendarEvent` 的 `no_overlapping_booking` 与 `check_status_transition` 在 model spec 中断言——非法跃迁被拒、存量回填、reserved 计入冲突、`cancelled`/`completed` 不挡。
- **Prior art**：对齐 `spec/models/calendar_event_spec.rb`（`have_db_column` 断言）、`storage_location_repository_row_spec` 的 `ensure_uniq_position` 唯一性测试范式、`my_module_status_spec` 的跃迁测试范式。

## Out of Scope

- 周期 / 重复预约的「发生实例展开」冲突检测（D2.4：仅校验基事件，系列内部分重叠为已知限制）。
- `reserved` 审批 SLA / 超时自动取消的具体机制（仅记录建议，D2.3）。
- 与 `wechat_gateway` addon 的企微推送通道集成（状态变更 / 24h 提醒 / 覆盖告警）——仅记录可能性。
- 启用数据库 `EXCLUDE` 约束（默认 deferred，与覆盖互斥）。

## Further Notes

- 兼容性：仅新增 `status` 列、两个 `validate`、`conflict_override` 内存标志；不影响现有 `calendar_event_created/updated` 通知、`CalendarEventReminderJob`（可顺带限定仅 `confirmed` 触发），不触及库存权限继承模型。
- 风险：TOCTOU 双写窗口（实验室低并发可接受）；`reserved` 槽位饿死（靠审批 SLA 缓解）；覆盖留痕不可省略（GLP）。
- 实现 issue 拆分见 `.scratch/equipment-reservation/issues/01-*.md` … `08-*.md`。
