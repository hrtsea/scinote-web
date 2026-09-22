# 05 — locale：状态文案 + overlap 错误（贯穿）

Type: task
Status: ready-for-agent
Blocked by:

**What to build:** 补全预约状态中/英文文案与冲突错误提示。

**Checklist**
- [ ] `config/locales/{en,zh-CN}.yml`：`calendar_event.status.reserved/confirmed/cancelled/completed`
- [ ] `activerecord.errors.models.calendar_event.overlap`（「该设备在此时段已被预约」）

**Done when:** 状态与冲突文案在两种 locale 下可用。
