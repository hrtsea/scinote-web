# 06 — Ruby intake + scinote_service_writer（F4/F5 草稿/确认）

**What to build:** `intake` 指令路由（`/new` `/use #ID` `/done` `/cancel`）+ 会话草稿；`scinote_service_writer` 封装 `Experiments::CreateService` 等，置 `created_by`=真实用户；草稿创建 → 本人 `/confirm` 锁定。

**Blocked by:** 03, 04, 05（需 Inbound 与至少一条通道）

**Status:** ready-for-agent

- [ ] `intake` 指令状态机（会话级草稿）
- [ ] `scinote_service_writer`：`Experiments::CreateService.call(user:, params)` 等
- [ ] 草稿 `/confirm` 锁定（状态语义待实例核）
- [ ] 文本 / 图片 / 文件落库（vision 抽文字）
