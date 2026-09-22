# 01 — 状态机：迁移 + enum + 跃迁校验（D1）

Type: task
Status: ready-for-agent
Blocked by:

**What to build:** 给 `calendar_events` 加 `status` 整数列（默认 `confirmed`），定义 `enum status: { reserved:0, confirmed:1, cancelled:2, completed:3 }`，手写 `validate :check_status_transition` 限定合法跃迁（`reserved→{confirmed,cancelled}`、`confirmed→{cancelled,completed}`），并为**存量行**回填 `confirmed`。

**Checklist**
- [ ] 迁移：`add_column :calendar_events, :status, :integer, default: 1, null: false`
- [ ] 迁移回填：`calendar_events.where(event_type: 0, status: nil).update_all(status: 1)`
- [ ] `app/models/calendar_event.rb`：`enum status:`（置于 `event_type` enum 旁）
- [ ] `validate :check_status_transition`，风格对齐 `my_module_status#next_in_same_flow`
- [ ] `before_validation`：新建且 `status` 为 nil 时设默认（自服务 `confirmed` / 审批开 `reserved`，见 08）
- [ ] `spec/models/calendar_event_spec.rb` 补 `have_db_column(:status)` + 跃迁用例
- [ ] 验证：存量预约 UI 仍正常显示、不报错

**Done when:** 模型含 status 枚举与跃迁校验；存量行均为 confirmed；model spec 绿。
