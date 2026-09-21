# 0007 — 设备预约状态机与冲突检测

## Status

Accepted（设计基线已定）。D2 冲突检测于 2026-09-21 经 `grill-with-docs` 压力测试细化：**按权限分级拦截 + exclusive 边界 + reserved 计入冲突 + 仅校验基事件**。核心选型（应用层 validation 为主、enum 状态机）未反转。

## Context

现状调研（`.scratch/equipment-reservation-research.md`）确认 `calendar_events` 表**无 status 列、无重叠校验**：所有行都是 `event_type = equipment_booking`，预约本身没有生命周期状态，且系统不阻止同一设备时间重叠的多次预约。需要给预约增加 (a) 生命周期状态机 与 (b) 双重预订（冲突）防护。

本 ADR 仅决定**架构形态与技术选型**（怎么做、为什么这么选），具体逐文件实现步骤见 `.scratch/equipment-reservation-state-machine-design.md`。

## Decision Drivers（约束，均来自一手源码）

- SciNote 全库**无 `aasm` / `state_machine` gem**（Gemfile 0 命中）；状态一律用 Rails 原生 `enum` + 手写校验（`label_printer`、`form_response`、`my_module_status` 均为范例）。
- `CalendarEventsController#create`/`#update` 已在事务中 `create!`/`update!` 并 `rescue ActiveRecord::RecordInvalid → 422`（`:48-51` / `:68-71`），新增 validation 自动生效，**控制器无需结构性改动**。
- 数据库 `btree_gist` 扩展已启用（`structure.sql:14-24`），具备加 `EXCLUDE` 约束的前提；但 `start_datetime/end_datetime` 为 `timestamp without time zone`，全天事件用独立 `date` 列（`start_date/end_date`，二者互斥）。
- 现有 `datetime_filter` 重叠谓词（`calendar_event.rb:24-28`）已用 `OR` 同时覆盖定时事件与全天事件两类相交，但其使用 inclusive `<=/>=`，**不适用于冲突判定**（见 D2 边界）。
- 设备预约权限入口已存在：`app/permissions/repository.rb` 的 `can_manage_equipment_bookings?`（受 `equipment_booking_enabled?` 门控）——这是「按权限分级拦截」的判断锚点。

## Decision

### D1 — 状态机：Rails `enum status:`，不引入 aasm

```ruby
# app/models/calendar_event.rb
enum status: { reserved: 0, confirmed: 1, cancelled: 2, completed: 3 }
```

**状态语义**

| 状态 | 值 | 占用时段？ | 说明 |
|---|---|---|---|
| `reserved` | 0 | 是 | 创建即占用；若启用审批流，表示「待审批」 |
| `confirmed` | 1 | 是 | 审批通过（无审批流时创建即置） |
| `cancelled` | 2 | 否 | 终态，释放时段 |
| `completed` | 3 | 否 | 终态，`end_datetime < now` 后由定时任务翻转 |

**状态跃迁矩阵**（✓ 合法，其余非法）

| From \ To | reserved | confirmed | cancelled | completed |
|---|---|---|---|---|
| reserved  | — | ✓ | ✓ | ✗ |
| confirmed | ✗ | — | ✓ | ✓ |
| cancelled | ✗ | ✗ | — | ✗ |
| completed | ✗ | ✗ | ✗ | — |

合法跃迁由手写 `validate :check_status_transition`（风格对齐 `my_module_status#next_in_same_flow` `:76-82`）约束；初始创建 `status` 为 nil 时跳过校验，由 `before_validation` / 控制器设默认值。

> **审批流作为配置项（非决策反转）**：新增开关 `equipment_booking_requires_approval`（沿用 `ApplicationSettings['equipment_booking_enabled']` 的既有配置机制）。
> - 关闭（默认，自服务）：创建即 `confirmed`，状态集实际表现为 `confirmed / cancelled / completed`。
> - 开启：创建为 `reserved`，由具备 `can_manage_equipment_bookings?` 者执行 approve 动作置 `confirmed`。
> 两种模式下 **enum 定义与跃迁矩阵不变**，仅初始值不同。

### D2 — 冲突检测：应用层 validation 为主，按权限分级拦截（EXCLUDE 降级）

#### D2.1 拦截策略（按权限）

- **普通用户 / 参与者**：重叠即**硬拦截**（`422`），由 `validate :no_overlapping_booking` + `#create`/`#update` 的 `rescue RecordInvalid` 出口保证。
- **管理员 / 设备负责人**（`can_manage_equipment_bookings?`）：可**强制覆盖**双写——在明知重叠时仍保存。
- **实现要点**：模型层 `validate :no_overlapping_booking` 仍负责检测；增加内存标志
  `attr_accessor :conflict_override`。控制器据 `current_user` 权限决定：无权限→不设置标志（硬拦截）；有权限且前端显式传 `override=true`→置 `conflict_override = true` 放行。
- **强制覆盖须留痕**：写一条 `Activity`（复用 `calendar_event_*` 活动类型或新增 override 类型），记录「操作者、被覆盖的冲突预约、时间」，满足 GLP 溯源。**严禁在无权限路径上静默跳过校验。**

#### D2.2 重叠判定（exclusive 边界）

- 重叠 = `A.start < B.end AND A.end > B.start`；**背靠背（`A.end == B.start`）不算冲突，可衔接**。
- 冲突检测使用**独立谓词**，不复用 `datetime_filter` 的 inclusive `<=/>=`（以免改变日历展示行为）：

```ruby
attr_accessor :conflict_override

validate :no_overlapping_booking, if: :equipment_booking?

def no_overlapping_booking
  return if conflict_override                      # 管理员/设备负责人显式覆盖时跳过
  return unless start_datetime.present? || start_date.present?

  s, e = range_bounds                              # 统一 time/date 为比较边界（见 SciNote 模型事实）
  clash = self.class
    .where(subject_type: subject_type, subject_id: subject_id)
    .where(status: BLOCKING_STATUSES)              # 占用中：reserved + confirmed
    .where.not(id: id)                             # 排除自身（更新时）
    .where('(start_datetime < ? AND end_datetime > ?) OR
            (start_date < ? AND end_date > ?)', e, s, e, s)
    .exists?
  errors.add(:base, :overlap) if clash
end
```
  风格对齐 `storage_location_repository_row#ensure_uniq_position` `:39-45`；错误文案 `I18n.t('activerecord.errors.models.calendar_event.overlap')`。

#### D2.3 占用中状态（确认：reserved 计入冲突）

- `BLOCKING_STATUSES = %i[reserved confirmed]`：待审批的 `reserved` **也占用槽位**（审批前即挡住他人）。
- 风险：长期未批的 `reserved` 可能饿死槽位 → 建议（非本 ADR 强制）对 `reserved` 设审批 SLA / 超时自动取消，留作后续 issue。

#### D2.4 周期 / 重复预约（确认：仅校验基事件）

- 仅校验**基事件**区间（`start_datetime/end_datetime`），与 D2.2 谓词一致。
- **已知限制**：重复系列（`frequency/interval/repeat_count/repeat_until`）中某些发生实例与其他预约重叠、但基事件区间不重叠时**漏检**。当前不阻断实现；后续可扩展「发生实例展开」issue。

#### D2.5 加固方案：DB `EXCLUDE` 约束（降级，与覆盖互斥）

```sql
ALTER TABLE calendar_events ADD CONSTRAINT no_overlap_bookings_excl
EXCLUDE USING gist (
  subject_id WITH =,
  tstzrange(start_datetime, end_datetime, '[)') WITH &&
) WHERE (event_type = 0 AND status IN (0,1));
```
- 优点：原子性，杜绝应用层 TOCTOU 双写窗口；range `[)` 与 exclusive 边界一致。
- **与 D2.1 权限覆盖互斥**：`EXCLUDE` 是 DB 级硬约束，对所有角色生效、无法按 `can_manage_equipment_bookings?` 豁免；管理员覆盖需临时 `DISABLE TRIGGER`/非常规手段，不可取。
- **结论**：因已选定「按权限分级 + 可覆盖」，**通常不采用 `EXCLUDE`**（接受实验室低并发下的 TOCTOU 风险）。仅当某部署**禁用覆盖且要求原子性**时，才启用 `EXCLUDE` 并放弃 D2.1 的覆盖能力——二者二选一，不可并存。

## SciNote 模型事实（已查证本地源码）

- `app/models/calendar_event.rb`：`:12-14` `enum event_type: { equipment_booking: 0 }`（全表唯一取值）；`:24-28` `datetime_filter` 重叠谓词（**inclusive**）；`:10` `before_save :reset_reminder_sent`；**全文无 `validates`、无 status 列**。
- `app/controllers/calendar_events_controller.rb`：`:33-51` `#create`（`transaction` 内 `create!`）；`:53-71` `#update`（`update!`）；`:48-51` / `:68-71` `rescue ActiveRecord::RecordInvalid → 422`；`:114-134` `calendar_event_params`（需 permit 新增 `status`）。
- `app/permissions/repository.rb`：`can_manage_equipment_bookings?` / `can_create/read_equipment_bookings?`（受 `equipment_booking_enabled?` 门控）—— 权限分级锚点。
- `app/models/storage_location_repository_row.rb:39-45` `ensure_uniq_position`：`where(...).where.not(id:).exists?` + `errors.add(:base, I18n.t(...))` —— 冲突校验参考范式。
- `app/models/my_module_status.rb:76-82` `next_in_same_flow`：`validate ..., if: -> { ... }` + `errors.add(:next_status, :different_flow)` —— 手写跃迁校验范式。
- `config/initializers/extends.rb:17-18` `TASKS_STATES`：既有 `enum` 状态定义约定。
- `db/structure.sql`：`:14-24` `btree_gist` 扩展已启用；`:392-414` `calendar_events` 建表（无 status、无唯一/EXCLUDE 约束、无时间索引）；`:6039-6070` 索引含 `index_calendar_events_on_subject`（subject_type, subject_id）。
- `spec/models/calendar_event_spec.rb:16-29`：现有 `have_db_column` 断言需补充 `status`。

## Consequences

- **正面**：状态机零新依赖、与 SciNote 既有约定一致、可测试；冲突检测按权限分级，兼顾「防误约」与「管理员灵活调度」；应用层（前置 UX）+ 可选 `EXCLUDE`（原子兜底）二选一，清晰。
- **负面 / 风险**：
  - **`EXCLUDE` 与「权限覆盖」互斥**（D2.5）：已选覆盖，故基本放弃 `EXCLUDE`，接受 TOCTOU 双写窗口（实验室低并发，可接受）。
  - **`reserved` 饿死槽位**（D2.3）：待审批预约长期占用，需后续 issue 补审批 SLA / 超时取消。
  - **周期预约漏检**（D2.4）：仅校验基事件，系列内部分重叠漏检，记为已知限制。
  - **覆盖留痕成本**（D2.1）：每次强制覆盖须写 `Activity`，实现不可省略，否则破坏 GLP 溯源。
- **兼容性**：仅新增 `status` 列、两个 validate、一个 `conflict_override` 内存标志；**不影响**现有 `calendar_event_created/updated` 通知、`CalendarEventReminderJob`（24h 提醒，可顺带限定仅 `confirmed` 触发），亦不触及库存权限继承模型。

## Considered Options（被弃备选）

- **引入 aasm 管理状态机**：被弃 —— SciNote 全库无此 gem，违反既有约定、增加依赖与学习成本。
- **仅用 DB EXCLUDE 约束、不做应用层校验**：被弃 —— 失去友好 `422` 前置提示，且 date/timestamp 混合与周期事件使其难以一步到位。
- **冲突软警告（允许保存）**：被弃 —— grill 中选定「按权限分级（普通用户硬拦截 + 管理员可覆盖）」优于纯软警告，既防误约又保留调度灵活性。
- **`reserved` 不计入冲突**：被弃 —— 选定审批前即占用槽位（更直观的「先到先占」语义），代价由审批 SLA 缓解。

## 待定项（Open questions，非本 ADR 范围）

- `equipment_booking_requires_approval` 默认值（建议默认关闭 = 自服务）。
- `reserved` 审批 SLA / 超时自动取消机制（缓解槽位饿死）。
- 前端（`app/javascript/vue/equipment_bookings/`）状态徽标 + 取消/审批/覆盖按钮的显隐逻辑（按 `can_manage_equipment_bookings?`）。
- 与 wechat_gateway addon 的企微推送通道（状态变更 / 24h 提醒 / 覆盖告警）—— 见现状调研 §8，仅记录集成可能性。

## 关联

- 现状调研：`.scratch/equipment-reservation-research.md`（§3 数据模型、§5 状态机/冲突结论、§6 权限、§7 通知）
- 实现设计：`.scratch/equipment-reservation-state-machine-design.md`（§3.1 已同步 exclusive 谓词 + 覆盖标志）
- 词汇：CONTEXT.md（预约 / 设备 / 预约状态 / 冲突 / 强制覆盖）
