# 0016 — SciNote Templates 现状确认 + Item Templates 以 addon 实现

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-009（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted

## Context

官网 SciNote Templates 六大模板类型（实验 / 工作流、协议 / SOP、Forms、物料、结果、库存）；代码库现状为五大类均已落在核心 `app/`。其中官网「自动提示用户使用预审批试剂 / 仪器 / 试剂盒」行为已由核心实现（协议库 Items 工具条可为协议挂库存项，`Protocol#load_from_repository` 实例化到任务时自动带入）。**唯一缺口**是把「一套预选库存」抽象成命名、可复用、可绑定多协议的一等公民对象，以及可选 `required` 强制标志（全仓 0 命中 `item_template` 命名概念）。

## Decision

- 以独立 Rails Engine `addons/protocol_item_templates/`（`Scinote::ProtocolItemTemplates::Engine`，`isolate_namespace`）承载 Item Templates 的**命名可复用抽象增强**（不重写核心自动带入逻辑）；**绝不修改核心 `app/`、不新增 `protocol_repository_rows` 表列**。
- 命名模板与协议的绑定存 addon 自有迁移表，经 `Extends` 合并注册（`config/initializers/extends.rb` 本体不改）；绑定服务在绑定期将命名模板的预选 `repository_rows` 展开写入既有 `protocol_repository_rows`（复用 `ProtocolRepositoryRow` 模型），实例化到任务的自动带入仍完全由核心负责。可选 `required` 标志存 addon 自有表。

## Consequences / 风险

- 若上游未来在核心实现自有 Item Templates，本 addon 的 `to_prepare` 装饰 / `app/decorators` 可能重复触发——覆盖点须记录在 `docs/开发计划/官方功能/templates/实现现状与开发计划.md` 并随上游演进复核。

## 关联

- 0009（协议导入 / 库协议 Items）
- `docs/开发计划/官方功能/templates/README.md`、`docs/开发计划/官方功能/templates/实现现状与开发计划.md`（PRD / Issues T1–T5）
- `docs/development/addon-dev-workflow.md`

> 序号说明：本 ADR 原占 ADR-009；`docs/开发计划/官方功能/protocol-sop-management/实现现状与开发计划.md` 中预留的「库协议版本通知」ADR 顺延为 **0017**（原 ADR-010）。
