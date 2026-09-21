# 0010 — 权限模型为「角色 + 用户分配」的集中式设计

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-003（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（图谱 + 代码核查）

## Context

权限模型现状：庞大的 `permissions/` 目录（13 个文件，按领域实体逐一划分）、`PermissionError` / `readable_by_user` 聚类，以及 `user_roles` + `user_assignments` + `team_assignments`。权限按实体显式建模（asset、experiment、project、repository、result、step、team、storage_location、form 等）。

## Decision

- 权限按实体**显式建模**，集中在 `permissions/<实体>.rb`。
- addon 新增权限谓词置于 `app/permissions/**/*.rb`（或引擎内同名路径），由 `config/initializers/canaid.rb` 自动发现（详见 0005 / 《Addon 机制综合指南》）。

## Consequences

- **新增领域实体必须配套对应的 `permissions/<实体>.rb` 及 user_role 权限集合**，否则将处于无防护状态。
- addon 切勿手改 `canaid.rb` 本体——靠 `app/permissions` 自动发现。

## 关联

- 0005（addon 注册约定）
- 0018、0019（Team Management / Integrations 现状评估）
