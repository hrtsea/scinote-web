# 0018 — Team Management 现状评估（核心已实现，仅外部计费 / 报告为 addon 候选）

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-011（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted

## Context

官网 Team Management 6 大能力 + 代码探查。团队 / 角色 / 权限 / 邀请 / `@` 协作 / 任务分配 / Overview·日历 / 报告 / 电子签名(addon) / 时区 / 审计 **已在 fork 实现**（逐项证据见 `docs/开发计划/官方功能/team-management实现现状与开发计划.md`）。核心 `app/` 搜 `billing` / `accounting` / `invoice` / `RESTful` 0 命中。

## Decision

1. **不在 fork 重建**核心 Team Management（违反 addon 铁律且收益为零）。
2. **W1（团队细分 / 限制访问 ELN 特定部分）判为上游计划级**：OSS fork 无 `parent_team` / `child_team`，需改造核心 `team.rb` + `readable_by_user` 链，**本 fork 不承接**。
3. **W2（外部伙伴 / 客户报告与计费 REST API 自动化）** 以独立引擎 `addons/partner_reporting/`（`Scinote::PartnerReporting::Engine`，`isolate_namespace`）承载，**绝不改核心 `app/`**；复用 `reports_controller` 导出 + `users/settings/webhooks_controller.rb` 雏形 + `Extends` 合并 + `app/permissions/**/*.rb` 自动发现；聚合复用 0015 的 `readable_by_user.joins(experiment: :project)` 范式；对外 API 客户端参考 `biomolecule_toolkit_client.rb`。

## Consequences / 风险

- W2 对外 CRM / ERP 契约未定（须 grill 明确字段 / 认证）；W1 强行 addon 化会突破铁律、rebase 冲突极高。W2 覆盖点仅限 addon 内，rebase 冲突低。

## 关联

- 0010（集中式权限模型）
- 0012（异步作业）
- 0014、0015（esignatures / project_insights 同口径不重建核心）
- `docs/开发计划/官方功能/team-managementREADME.md`、`docs/开发计划/官方功能/team-management实现现状与开发计划.md`（PRD / 缺口 W1–W2）
