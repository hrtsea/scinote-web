# 0012 — 导出 / 通知 / 提醒使用异步作业

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-005（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（图谱）

## Context

长耗时任务执行方式现状：26 个 job；`repository_*_zip_export_job`、`team_zip_export_job`、通知 / 提醒 job；后端为 `delayed_job`。

## Decision

- 导出、通知、提醒等长耗时任务推入 **DelayedJob** 异步执行。
- 不应阻塞请求路径。

## Consequences

- 新增导出 / 批量任务应走 `app/jobs` 而非控制器同步处理。
- 与 0014（esignatures 导出证明）、0015（project_insights 聚合）共用异步范式。

## 关联

- 0014（esignatures：全量导出附签名证明）
- 0015（project_insights：聚合服务）
