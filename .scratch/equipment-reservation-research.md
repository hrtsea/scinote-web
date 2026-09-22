# 设备预约（Equipment Scheduling / Equipment Bookings）调研

> 调研时间：2026-09-20
> 方法：代码仓一手源码核对（F:\eln 用户工程 + E:\ 参考源码）+ SciNote 官方知识库文档
> 范围：SciNote 开源 ELN 中「设备预约 / 仪器排程」功能的现状、数据模型、流程、权限、通知集成点

## 1. 结论摘要

- SciNote **内置**了设备预约功能，UI 名为 **Equipment Scheduling**（左侧菜单 "Equipment bookings"，图标 `sn-icon-equipment-scheduling`），代码层命名为 `equipment_booking*` / `calendar_events`。
- **不是第三方插件**：代码位于核心 `app/`、`config/`、`db/` 目录，非独立 gem/engine。
- 本质：**把「设备/仪器」当作库存条目（`RepositoryRow`），在它上面挂日历事件（`calendar_events`，`event_type = equipment_booking`）**。即用连续 `start_datetime/end_datetime` 排程，而非离散时段（timeslot）。
- **无预约状态机**：表中没有 `status/state` 列，没有 `confirmed/pending/cancelled` 等状态；只有 `reminder_sent` 布尔标记。
- **由订阅开关控制**：`ApplicationSettings['equipment_booking_enabled']`（环境变量 `APP_STTG_EQUIPMENT_BOOKING_ENABLED`），关闭时显示 promo 推广页。官方文档说明该功能在 **Professional / Platinum 计划**可用（其他计划可试用）。
- **权限继承自库存**：与底层 Inventory 的访问/权限设置一致。

## 2. 启用与计划限制（官方文档一手来源）

- 入口：主菜单 locations 图标下的 Equipment Scheduling 日历。
- 计划：`Equipment Scheduling is available on Professional and Platinum plans. Teams on the other plans can try it with a free trial.`（knowledgebase.scinote.net/en/knowledge/equipment-scheduling）
- 代码门控：`app/models/repository.rb` → `Repository.equipment_booking_enabled?` 返回 `ApplicationSettings.instance.values['equipment_booking_enabled'] == true`；关闭时 `EquipmentBookingsController#check_calendar_events_enabled` 渲染 `promo` 页（app/views/equipment_bookings/promo.html.erb）。

## 3. 数据模型（源码一手来源，F: 与 E: 两仓一致）

### 表 `calendar_events`（预约/排程存储）
来源：`db/structure.sql`

| 列 | 说明 |
|---|---|
| `id` | bigint |
| `name` | varchar（事件标题） |
| `subject_type` / `subject_id` | 多态，实际为 `RepositoryRow`（被预约的库存条目/设备） |
| `team_id` | bigint |
| `start_datetime` / `end_datetime` | timestamp（排程起止） |
| `start_date` / `end_date` | date（全天事件，E: 由 20260616 迁移加入） |
| `created_by_id` | bigint（User） |
| `event_type` | integer，**枚举唯一取值 `equipment_booking: 0`**（`app/models/calendar_event.rb:12`）——即所有行都是设备预约 |
| `event_sub_type` | varchar（子类型，如 使用/校准/维护/其他） |
| `metadata` | jsonb，默认 `{}` |
| `frequency` / `interval` / `interval_unit` / `repeat_count` / `repeat_until` | 周期性/重复排程 |
| `reminder_sent` | boolean，默认 false（提醒已发送标记） |

### 表 `calendar_event_participants`（参与者 = 被通知的使用者）
- `calendar_event_id`、`user_id`，唯一索引 `(calendar_event_id, user_id)`
- 模型 `app/models/calendar_event_participant.rb`：`belongs_to :calendar_event` + `belongs_to :user`

### 关联
- `CalendarEvent` → `belongs_to :subject, polymorphic: true`（实际 `RepositoryRow`）→ `belongs_to :team` → `belongs_to :created_by (User)` → `has_many :calendar_event_participants, dependent: :destroy` → `has_many :users, through: :calendar_event_participants`
- 即：**预约挂在库存条目（RepositoryRow）上的日历事件，参与者是多名 User**。

### 迁移（均为 2026 新增，证实是较新功能）
- `20260420095412_add_calendar_events.rb`：建 `calendar_events` + `calendar_event_participants`
- `20260508105328_add_frequency_fields_to_calendar_events.rb`：重复排程字段
- `20260526000000_add_reminder_sent_to_calendar_events.rb`：`reminder_sent`
- E: 额外 `20260616085134_add_date_fields_to_calendart_events.rb`：`start_date/end_date`

## 4. 用户流程（官方文档一手来源）

三种创建预约事件（booking event）的方式，本质都是「向某个库存项添加日程事件」：

1. **从设备排程日历创建**：主菜单 Equipment → 日历上 `+New event` → 填写标题/事件类型/团队成员/时间范围 → Create Event。
2. **从库存项工具栏创建**：Inventory 定位条目 → 底部工具栏 `Create Event` → 填写 → Create Event。
3. **从库存项卡片 Schedule 区创建**：打开条目卡片（库存列表 / 任务中 / 富文本 `#` 哈希链接）→ Schedule 区 `Create Event`。

事件字段：Title、Event type（使用/校准/维护/其他）、Assigned team members、Date and time range。
日历视图：Daily / Weekly / Monthly（顶部切换）。

## 5. 状态机 / 冲突检测（代码结论）

- **无独立状态列**：`calendar_events` 无 `status/state`；`event_type` 仅 `equipment_booking` 一个值；无 `confirmed/pending/cancelled/approved`。
- **冲突/重叠处理**：官方文档与代码均未发现双重预订检测/阻止逻辑（代码仓搜索 `overlap/conflict/double` 无业务命中）。即系统**不阻止同一设备时间重叠的多次预约**。
- 取消 = 删除 `calendar_event`（`CalendarEventsController#destroy`）。

## 6. 权限

- 继承自库存：`Equipment Scheduling follows the same access and permission settings as the underlying inventory.`（官方文档）
- 代码门控：`app/permissions/repository.rb` 的 `can_create/manage/read_equipment_bookings?` 全部受 `Repository.equipment_booking_enabled?` 控制；`app/services/toolbars/repository_rows_service.rb` 的 `create_event_action` 同样门控。

## 7. 通知 / 提醒 / 活动日志（源码一手来源）

- **提醒 Job**：`app/jobs/calendar_event_reminder_job.rb`（`REMINDER_WINDOW = 24.hours`）扫描 `event_type: :equipment_booking` 且 `reminder_sent: false`、24h 内开始的事件并触发通知。
- **通知类**：`app/notifications/equipment_booking_reminder_notification.rb`（`EquipmentBookingReminderNotification < BaseNotification`，subtype `:equipment_booking_reminder`），`after_deliver` 置 `reminder_sent = true`；点击跳转库存条目 `#schedule-section`。
- **收件人注册**：`config/initializers/extends/notification_extends.rb` 注册 `equipment_booking_reminder → CalendarEventReminderRecipients`；`calendar_event_created/updated/deleted_activity → Assigned/DeletedCalendarEventRecipients`；并在 `NOTIFICATIONS_GROUPS.repository.equipment_scheduling` 分组。
- **活动日志**：`config/initializers/extends.rb` ACTIVITY_TYPES：`calendar_event_created(493)`、`calendar_event_updated(494)`、`calendar_event_deleted(495)`、`calendar_event_participant_created(496)`、`calendar_event_participant_deleted(497)`。
- **邮件**：无独立 `EquipmentBookingMailer`；由通用 `BaseNotification` 框架（站内 + 邮件）统一投递。

## 8. 与微信网关（wechat_gateway addon）的集成机会（前瞻，非现状）

本 addon 已实现：企微回调解密（`WecomCrypto`）、iLink 私聊（`IlinkBridge`）、Inbound 统一入口（`Inbound#receive`）、绑定解析（`BindingResolver`，把企微身份映射到 SciNote user）。设备预约的天然集成点：

- **预约创建/变更 → 推送给参与者**：`calendar_event_created/updated` 活动已产生收件人，可挂一个 notifier 经 `Wechat::CorpApi#message_send`（gemspec 已依赖 `wechat`，仅出站）把预约摘要发给参与者的企微。
- **24h 提醒 → 企微消息**：复用 `CalendarEventReminderJob`，在 `EquipmentBookingReminderNotification#after_deliver` 之外追加企微推送通道。
- **前提**：需 `wechat_user_bindings`（ticket 02 已 resolved）把 SciNote user ↔ 企微 userid 打通；本调研未涉及该桥接的实现细节，仅记录集成可能性。

## 9. 两仓库差异（次要）

- E: 参考源码略新：多出 `calendar_event_serializer.rb`、`calendar_event_participant_serializer.rb`、`app/notifications/recipients/calendar_event_reminder_recipients.rb`、`assigned_calendar_event_recipients.rb`、global_activities 引用，及 20260616 date 字段迁移。
- F:\eln 同样具备 `calendar_event_participant.rb` 与含 `start_date/end_date` 的 `db/structure.sql`，核心功能等价。

## 10. Sources

- 代码仓（F: 与 E: 两仓一致）：
  - `app/models/calendar_event.rb:12`（event_type 枚举）
  - `app/models/calendar_event_participant.rb`
  - `app/models/repository.rb`（equipment_booking_enabled?）
  - `app/controllers/equipment_bookings_controller.rb`、`app/controllers/calendar_events_controller.rb`
  - `app/notifications/equipment_booking_reminder_notification.rb`
  - `app/jobs/calendar_event_reminder_job.rb`
  - `config/initializers/extends/notification_extends.rb`、`config/initializers/extends.rb`（ACTIVITY_TYPES）
  - `config/routes.rb`（resources :equipment_bookings / :calendar_events）
  - `app/permissions/repository.rb`、`app/services/toolbars/repository_rows_service.rb`
  - `db/structure.sql`、`db/migrate/20260420*` / `20260508*` / `20260526*` / `20260616*`
- 官方文档：https://knowledgebase.scinote.net/en/knowledge/equipment-scheduling （How to Use Equipment Scheduling in SciNote，Copyright © 2026 SCINOTE LLC）

---

*注：本调研为只读，未修改任何代码。关键词搜索证据（`reservation`/`instrument`/`timeslot`/`bookable`/`availability` 全库 0 命中，功能用语是 equipment booking / scheduling）佐证上述命名结论。*
