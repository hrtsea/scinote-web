# 设备预约：状态机 + 冲突检测 实现设计调研

> 调研时间：2026-09-20
> 方法：一手源码核对（F:\eln\scinote-web-develop）+ SciNote 官方文档
> 前置：`.scratch/equipment-reservation-research.md`（现状调研，确认 `calendar_events` 现状无 status、无冲突校验）
> 目标：给 SciNote 现有 Equipment Bookings 增加「预约状态机」与「冲突（重叠）检测」

## 0. 设计摘要（TL;DR）

| 维度 | 决策（默认） | 依据 |
|---|---|---|
| 状态机实现 | Rails 原生 `enum status:`（整数映射），**不引入 aasm** | SciNote 全库无 aasm，`enum` 是既有约定（`label_printer`/`form_response` 风格） |
| 状态集 | `reserved → confirmed → completed`，均可 `→ cancelled` | 最小可用 + 留出审批扩展位（见 §2 决策点） |
| 冲突检测（主） | **应用层 validation**（`validate :no_overlapping_booking`），复用现有 `datetime_filter` 重叠谓词 | 与 `storage_location_repository_row#ensure_uniq_position` 同风格、可测试、`#create`/`#update` 已 `rescue RecordInvalid → 422` 自动生效 |
| 冲突检测（加固，可选） | Postgres `EXCLUDE USING gist` 约束（`btree_gist` 已启用） | 解决并发竞态（TOCTOU）；但需先统一 time/date 维度，复杂度高 → 作为第二步 |
| 落点 | `calendar_event.rb` 加 enum + 两个 validate；迁移加 `status` 列；locale 加文案 | 控制器无需结构性改动 |

## 1. 领域术语（建议并入 CONTEXT.md）

| Term | Meaning | Avoid |
|---|---|---|
| **预约 / Reservation** | `calendar_event`（`event_type = equipment_booking`），挂在某个 `RepositoryRow`（设备库存条目）上，含起止时间 | 不要假设有独立 `Booking` 模型 |
| **设备 / Equipment** | 可被预约的库存条目（`RepositoryRow`）；预约的 `subject` | 不要与「仪器校准」等子类型混淆 |
| **预约状态 / Reservation Status** | 预约生命周期状态（`reserved/confirmed/cancelled/completed`），决定该预约是否占用设备时段 | 不要与 `event_type`（使用/校准/维护）混淆——那是子类型不是状态 |
| **冲突 / 双重预订（Conflict / Double-booking）** | 同一 `RepositoryRow` 上两个「占用中」预约的时间区间相交 | 注意 cancelled/completed 不计入冲突 |
| **时间区间 / Time range** | 定时事件 `[start_datetime, end_datetime]`；全天事件 `[start_date, end_date]` | 两类并存，冲突检测需统一处理（见 §3.4） |

## 2. 状态机设计

### 2.1 状态集（默认提案）

```ruby
# app/models/calendar_event.rb
enum status: { reserved: 0, confirmed: 1, cancelled: 2, completed: 3 }
```

- `reserved`（初始）：创建即占用时段，冲突检测视为「占用中」。
- `confirmed`：审批通过后（若启用审批流）；无审批流时创建即置 `confirmed`。
- `cancelled`（终态）：用户取消，释放时段，不计入冲突。
- `completed`（终态）：`end_datetime < now` 后由定时任务翻转，不计入冲突。

**决策点（需用户拍板）— 是否需要审批流？**
- 自服务（默认，简单）：创建即 `confirmed`，状态集退化为 `confirmed / cancelled / completed`。
- 需审批（共享贵重仪器常见）：`reserved → confirmed`，由有 `can_manage_equipment_bookings?` 权限者审批。
- 本设计按「含审批位」给出完整状态集，若取自服务则创建时直接写 `confirmed`，状态机代码不变。

### 2.2 合法跃迁（手写校验，沿用 `my_module_status#next_in_same_flow` 风格）

```ruby
BLOCKING_STATUSES = %i[reserved confirmed].freeze

validate :check_status_transition, if: :status_changed?

def check_status_transition
  return if status_was.nil?
  allowed = {
    'reserved'  => %w[confirmed cancelled],
    'confirmed' => %w[cancelled completed],
    'cancelled' => [],
    'completed' => []
  }
  unless allowed[status_was]&.include?(status)
    errors.add(:status, :illegal_transition,
               message: I18n.t('activerecord.errors.models.calendar_event.illegal_transition'))
  end
end
```

- 初始创建 `status` 为 nil → 跳过校验，由 `before_validation` / 控制器设默认值。
- `completed` 翻转由 `CalendarEventFinalizeJob`（或复用 Delayed Job，与本 repo 队列一致，见 CONTEXT.md「Delayed Job」）按 `end_datetime` 批量处理；不阻塞请求。

### 2.3 代码落点

- 模型：`app/models/calendar_event.rb`（全文仅 37 行，现无 `validates`、无 status——直接补）。
- 控制器：`CalendarEventsController#create`（`:33-51`）在 `create!` 前 merge `status: :reserved`（`equipment_booking?` 时）；`#update`（`:53-71`）允许 `status` 字段（需在 `calendar_event_params` `:114-134` permit 中加入 `status`）。
- **无需改救援结构**：`#create`/`#update` 已 `rescue ActiveRecord::RecordInvalid → 422`（`:48-51` / `:68-71`），新增 validation 自动走此出口。

## 3. 冲突检测设计

### 3.1 应用层 validation（主方案，按权限分级拦截）

冲突检测使用**独立 exclusive 谓词**（不复用 `datetime_filter` 的 inclusive `<=/>=`，以免改变日历展示）：重叠 = `A.start < B.end AND A.end > B.start`，背靠背（`A.end == B.start`）可衔接。

```ruby
attr_accessor :conflict_override   # 由控制器按操作者权限设置

validate :no_overlapping_booking, if: :equipment_booking?

def no_overlapping_booking
  return if conflict_override      # 管理员/设备负责人显式覆盖时跳过
  return unless start_datetime.present? || start_date.present?

  s, e = range_bounds              # 统一 time/date 为比较边界（见 §3.4）
  clash = self.class
    .where(subject_type: subject_type, subject_id: subject_id)
    .where(status: BLOCKING_STATUSES)                 # 占用中：reserved + confirmed
    .where.not(id: id)                               # 排除自身（更新时）
    .where('(start_datetime < ? AND end_datetime > ?) OR
            (start_date < ? AND end_date > ?)', e, s, e, s)
    .exists?

  errors.add(:base, :overlap) if clash
end
```

**分级拦截**：
- 普通用户：控制器不设置 `conflict_override` → 重叠即 `422`（沿用 `#create`/`#update` 的 `rescue RecordInvalid`）。
- 管理员 / 设备负责人（`can_manage_equipment_bookings?`）：前端传 `override=true` 时控制器置 `conflict_override = true` 放行；**强制覆盖须写 `Activity` 留痕**（记录操作者、被覆盖的冲突预约）。

- `subject_type/subject_id` 有联合 btree 索引（`index_calendar_events_on_subject`，`structure.sql:6039-6070`），冲突查询可命中。
- 错误文案走 `I18n.t('activerecord.errors.models.calendar_event.overlap')`（与本 repo `errors.add(:base, I18n.t(...))` 约定一致）。

### 3.2 数据库层 EXCLUDE 约束（加固方案，可选）

`btree_gist` 扩展**已启用**（`structure.sql:14-24`），具备加 `EXCLUDE` 约束的前提：

```sql
ALTER TABLE calendar_events ADD CONSTRAINT no_overlap_bookings_excl
EXCLUDE USING gist (
  subject_id WITH =,
  tstzrange(start_datetime, end_datetime, '[)') WITH &&
) WHERE (event_type = 0 AND status IN (0,1));
```

- 优点：原子性，杜绝并发双写竞态（TOCTOU）。
- 代价/限制（见 ADR-0007）：
  1. `start_datetime/end_datetime` 是 `timestamp without time zone`，需先规整时区或改用 `timestamptz`；
  2. 全天事件用 `date` 列，与 `timestamp` 不在同一 range——需先统一为单一 `tsrange`（如全天映射为该日 00:00–24:00 的 timestamp，或把 date 也纳入同一表达式）；
  3. 周期性（`frequency/interval/...`）事件目前代码不展开发生实例，EXCLUDE 只约束基事件区间，重复实例的重叠不被拦截；
  4. 迁移需 raw SQL（`structure.sql` 管理，非 schema.rb），且约束与现有 `subject_id` 联合需 `btree_gist`（已满足）。

**建议**：先上应用层（§3.1）快速可用、可测。**与「按权限覆盖」互斥**——`EXCLUDE` 是 DB 级硬约束、无法按 `can_manage_equipment_bookings?` 豁免，故已选定覆盖能力后**通常不采用 EXCLUDE**（接受实验室低并发下的 TOCTOU 风险）；仅当某部署禁用覆盖且要求原子性时才启用（此时放弃 D2.1 的覆盖能力，二者二选一）。

### 3.3 竞态说明

应用层在并发下存在 TOCTOU（两请求同时读无冲突→都写）。实验室设备预约并发度低，可接受；EXCLUDE 约束是根治手段。无需为此引入乐观锁。

### 3.4 时间维度统一（edge case）

`calendar_event` 同时有 `start_datetime/end_datetime`（timestamp）与 `start_date/end_date`（date），二者互斥（`calendar_event_params` `:115-121` 二选一）。冲突校验须覆盖三种相交：定时↔定时、全天↔全天、定时↔全天（将 date 视为当日 00:00–23:59 或 00:00–次日 00:00）。`datetime_filter` 现有谓词已用 `OR` 同时覆盖两类，可直接复用其比较式，仅把参数换成 `self` 的边界并加 `status`/`subject` 过滤与 `id` 排除。

## 4. 与现有通知 / 微信网关的集成

- **状态变更通知**：复用 `calendar_event_created/updated/deleted_activity` + `CalendarEvent*Recipients`（见现状调研 §7）。审批通过（`reserved→confirmed`）或取消（`→cancelled`）时，可在 `check_status_transition` 通过后由 `after_save` 触发对应 Activity/Notification，参与者收到站内+邮件。
- **24h 提醒**：现有 `CalendarEventReminderJob`（`REMINDER_WINDOW = 24.hours`）已扫描 `equipment_booking` 事件；可加：仅对 `confirmed` 状态提醒（cancelled 不提醒）。
- **微信推送（前瞻）**：wechat_gateway addon 已具备企微出站能力（`Wechat::CorpApi#message_send`）。在 `EquipmentBookingReminderNotification` / 状态变更 Activity 的 notifier 中加企微通道，把预约摘要/提醒推到参与者企微，前提仍是 `wechat_user_bindings` 打通（现状调研 §8）。

## 5. 具体实现清单（按文件）

1. **迁移** `db/migrate/2026xxxx_add_status_to_calendar_events.rb`
   - `add_column :calendar_events, :status, :integer, default: 0, null: false`
   - `add_index :calendar_events, :status`
   - （可选 EXCLUDE）raw SQL `EXCLUDE ...`（见 §3.2，需先解决时区/date 统一）
2. **模型** `app/models/calendar_event.rb`
   - `enum status: { reserved: 0, confirmed: 1, cancelled: 2, completed: 3 }`
   - `validate :check_status_transition, if: :status_changed?`
   - `validate :no_overlapping_booking, if: :equipment_booking?`
   - `before_validation :set_default_status, on: :create`（无审批时设 `confirmed`）
   - `BLOCKING_STATUSES` 常量
3. **控制器** `app/controllers/calendar_events_controller.rb`
   - `calendar_event_params`（`114-134`）permit 加入 `status`
   - `#create` merge 默认 `status`（无需改 rescue）
4. **locale** `config/locales/en.yml`（及中文 locale 若启用）
   - `activerecord.errors.models.calendar_event.overlap` / `.illegal_transition`
   - 状态显示名 `activerecord.attributes.calendar_event.statuses.*`
5. **前端（Vue）** `app/javascript/vue/equipment_bookings/`
   - `calendar_view.vue` / `event_create_repository_row.vue`：状态徽标 + 取消/审批操作按钮（按 `can_manage_equipment_bookings?` 显隐）
6. **测试**
   - `spec/models/calendar_event_spec.rb`（`16-29` 的 `have_db_column` 列表补 `status`）；新增状态跃迁用例 + 重叠冲突用例（同设备重叠→invalid；cancelled 不冲突；不同设备可重叠）
   - `spec/requests/calendar_events_spec.rb`：重叠创建返回 422

## 6. 验证标准（Goal-Driven）

- [ ] 迁移后 `calendar_events` 有 `status` 列，默认 `reserved`/`confirmed`，现有数据回填正确。
- [ ] 同设备时间重叠创建 → `RecordInvalid` → 控制器返回 422，前端提示冲突。
- [ ] `cancelled`/`completed` 预约不计入冲突（可被新预约覆盖其时段）。
- [ ] 非法状态跃迁（如 `completed → reserved`）被 `check_status_transition` 拒绝。
- [ ] 不同 `RepositoryRow`（不同设备）时间重叠可共存。
- [ ] 全天事件与定时事件混合重叠被正确识别。
- [ ] 现有 `CalendarEventReminderJob` 行为不被破坏（仅 `equipment_booking` 已满足；按需限定 `confirmed`）。

## 7. Sources（一手）

- `app/models/calendar_event.rb`（enum event_type :12-14；datetime_filter :24-28；before_save :10；全文无 validates）
- `app/controllers/calendar_events_controller.rb`（`#create` :33-51；`#update` :53-71；rescue 422 :48-51/:68-71；`calendar_event_params` :114-134）
- `app/models/storage_location_repository_row.rb:17-24,39-45`（`ensure_uniq_position` 参考范式）
- `app/models/my_module_status.rb:76-82`（`next_in_same_flow` 手写跃迁校验范式）
- `config/initializers/extends.rb:17-18`（`TASKS_STATES`）
- `db/structure.sql`（`calendar_events` 建表 :392-414；索引 :6039-6070；`btree_gist` :14-24）
- `spec/models/calendar_event_spec.rb:16-29`（现有列断言，需补充）
- 现状调研：`.scratch/equipment-reservation-research.md`（§3 数据模型、§5 状态机/冲突结论、§7 通知）
- 官方文档：https://knowledgebase.scinote.net/en/knowledge/equipment-scheduling

---

*本设计为只读调研，未修改任何代码。状态集与「是否需审批流」为建议默认，待用户确认（§2.1 决策点）。*
