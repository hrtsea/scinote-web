# 0019 — Integrations & API 现状评估（核心已实现 8 项，3 项外部集成为 addon 候选）

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-012（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted

## Context

官网 Integrations & API 罗列 1 个 RESTful API + 11 项开箱集成；代码库核查（逐项文件:行证据见 `docs/开发计划/官方功能/integrations-api实现现状与开发计划.md`）。

## Decision

1. **已实现（核心 `app/`，非 addon，不重建）**：RESTful API（`app/controllers/api/v1` 40 控制器 + `app/controllers/api/v2` 21 控制器）、Webhooks、Protocols.io 导入（0009）、Office for the Web / WOPI、Open Vector Editor、ChemAxon Marvin、Zebra 标签打印、FLUICS 云打印。
2. **缺失（全仓 0 命中）**：Ganymede、Quartzy、Gilson Connect。若决定承接，**各自以独立 Rails Engine addon**（`Scinote::Ganymede::Engine` / `Scinote::Quartzy::Engine` / `Scinote::GilsonConnect::Engine`，`isolate_namespace`）实现，**绝不改核心 `app/`**；复用 FLUICS 的 `api_client` + `sync_service` 云同步范式、`label_printers_controller` 设置页 UI 范式、以及 `activities` 记录范式。
3. 三项均涉第三方认证 / 数据契约 / 合规，须经 `/grill` 明确字段映射后再脚手架；建议先做单向数据流入 MVP，避免范围膨胀（Ganymede 风险最高）。

## Consequences / 风险

- 本环境（Windows，无 GitHub / 外网代理）无法对三项做第三方联调，仅能离线写客户端与契约测试。
- 若上游未来原生实现这些集成，本 addon 的 `Extends` 合并 / decorator 可能重复触发（参照 0013~0018 冲突提示）。

## 关联

- 0009、0010、0013~0018（同口径不重建核心 / addon 化候选）
- `docs/开发计划/官方功能/integrations-apiREADME.md`、`docs/开发计划/官方功能/integrations-api实现现状与开发计划.md`
