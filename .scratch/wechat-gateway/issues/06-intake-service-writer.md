# 06 — Ruby intake + scinote_service_writer（F4/F5 草稿/确认）

> ⚠️ **本 issue 已拆分 / 部分交付（2026-09-24 重组标记）**：`intake.rb` 与 `scinote_service_writer.rb` 实际已落地，但本 issue 原文已过时：
> - 原文列出的 `/new`、`/use #ID` 等**指令名已废弃**，现统一为 `<动词><实体>` 四动词矩阵（`/newproject` `/setexp` `/getexp` `/listexp` …，见 `17` 与 `docs/指令参考.md`）。
> - 原文未能覆盖的**安全缺口**已拆为独立 ticket：可见性基座（`11`）、读侧闸门（`12`）、写权限矩阵（`13`）、`#<ID>` 不切草稿（`16`）。
> - **追加落点纠正（domain-model 核实）**：Experiment **无** assets/results 容器；真实文件/图谱/结果挂在 `MyModule`（Task）。当前纯文本仅降级落到 `MyModule.description`；真实 `Result`/`Asset`/`RepositoryRow` 属独立能力建设（见 `docs/指令参考.md` §四.6），**建议新增 ticket**。

**What to build（原始描述，仅作历史）:** `intake` 指令路由（`/new` `/use #ID` `/done` `/cancel`）+ 会话草稿；`scinote_service_writer` 封装 `Experiments::CreateService` 等，置 `created_by`=真实用户；草稿创建 → 本人 `/confirm` 锁定。

**Blocked by:** 03, 04, 05（需 Inbound 与至少一条通道）

**Status:** ready-for-agent

- [ ] `intake` 指令状态机（会话级草稿）
- [ ] `scinote_service_writer`：`Experiments::CreateService.call(user:, params)` 等
- [ ] 草稿 `/confirm` 锁定（状态语义待实例核）
- [ ] 文本 / 图片 / 文件落库（vision 抽文字）
