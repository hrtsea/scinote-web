# 0009 — 协议从外部源导入（Protocols.io）

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-002（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（图谱 + 代码核查）

## Context

系统支持从外部协议源（Protocols.io）导入，并维护多版本导入器。代码现状：`ProtocolImporters::ProtocolsIo::V3::StepComponents#name`（421 调用）、`ExternalProtocolsController#new`（232），以及 `utilities/protocol_importers`、`services/protocol_importers`、`protocol_importers_v2/v3` 目录。

## Decision

- 系统支持多版本协议导入（`protocol_importers` v2 / v3）。
- 各导入器版本间须保持**向后兼容**。

## Consequences

- 新增 / 调整导入器版本时不得破坏既有导入产物。

## 关联

- 0013（ai_protocols：生成内容对齐 `ImportProtocolService` 的 `steps_params` schema）
- 0016（protocol_item_templates：协议库「Items」自动带入）
- 0017（protocol_version_notifier：库版本变更通知）
