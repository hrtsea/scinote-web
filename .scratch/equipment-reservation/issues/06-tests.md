# 06 — 测试：状态机 + 冲突 feature 测试

Type: task
Status: ready-for-agent
Blocked by: 01, 02, 05

**What to build:** 模型 spec 更新 + 冲突检测集成测试（只测外部行为）。

**Checklist**
- [ ] `spec/models/calendar_event_spec.rb`：enum 值、跃迁非法拒绝、存量回填
- [ ] 冲突：同设备重叠→422；背靠背→通过；cancelled/completed 不挡；reserved 计入冲突
- [ ] 分级：管理员 override 成功且留痕；普通用户 override 被拒

**Done when:** RSpec 覆盖状态机与冲突分层；spec 绿。
