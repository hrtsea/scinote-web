# 0017 — 协议库版本变更通知以 addon 形式实现（protocol_version_notifier）

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-010（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted

## Context

官网「Protocol & SOP Management」明确「If the version in the repository changes, you will be notified」；代码库现状：`Protocol` 已具备版本体系（`in_repository_published_original` / `published_version`、`version_number`、`newer_than_parent?`、`revert_protocol` 权限），但**全仓无任何「协议版本变更 → 通知关联任务」的服务 / observer**（搜索 `ProtocolUpdated` / `notify` / `protocol.*changed` 0 命中）。即「库版本变更通知」为**真实缺失项**。

## Decision

- 以独立 Rails Engine `addons/protocol_version_notifier/`（`Scinote::ProtocolVersionNotifier::Engine`，`isolate_namespace`）承载全部版本变更通知逻辑；**绝不修改核心 `app/`**。
- **触发与接收（复用，不新建基础设施）**：
  - 订阅 `Protocol` 的版本变更事件——优先复用 `Protocol` 已 `include ObservableModel` 的广播能力；若其不对外发 `ActiveSupport::Notifications`，则改用引擎 `to_prepare` 装饰 `Protocol` 的发布动作。
  - 接收人取 `Protocol#all_linked_children` → `linked_my_modules` → 任务 `designated_users`，并经 `can_read_protocol_in_repository?` 过滤；推送复用 `Activities::CreateActivityService` 与 `app/notifications/`，不另造渠道。
  - UI 提示经 `app/decorators` 注入任务协议面板，受 `newer_than_parent?` 驱动；「一键 revert」完全依赖核心既有 `revert_protocol` 权限与逻辑，addon 不重写。

## 范围边界（经 `/grill`）

- 本期**仅**做 G1 版本变更通知。
- **G2 重新定性**——步骤完成人实际已由 `complete_step` / `uncomplete_step` 活动以 `owner = current_user` 记录，数据层已满足「由谁完成」，仅 UI 未内联展示，可由 addon 侧读取 `activities` 实现、**无需改核心**；独立的 `completed_by` 列不推荐（需核心迁移，违反 addon 铁律）。
- 与「AI 辅助创建协议」相关的绿地工作属独立 0013（`addons/ai_protocols`），不在此重复。

## Consequences / 风险

- 若上游未来在核心实现自有版本通知，本 addon 的 `to_prepare` 订阅 / decorator 可能重复触发——覆盖点须记录在 `docs/开发计划/官方功能/protocol-sop-management/实现现状与开发计划.md`。
- 同一协议多次发布需去重，避免刷屏。

## 关联

- 0009（协议导入）
- 0016（protocol_item_templates）
- `docs/开发计划/官方功能/protocol-sop-management/README.md`、`docs/开发计划/官方功能/protocol-sop-management/实现现状与开发计划.md`（PRD / Issues P1–P4）
