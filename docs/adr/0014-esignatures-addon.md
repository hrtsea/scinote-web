# 0014 — 21 CFR Part 11 电子签名以 addon 形式实现（esignatures）

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-007（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（2026-09-01 已实现并接入）

## Context

官网「Regulatory Compliance / 21 CFR Part 11」要求电子签名须 unique to one individual、indisputably linked、prevent fraudulent use；代码库现状为全仓 0 命中 `electronic_signature` 模型 / 服务 / UI，属完全缺失。

## Decision

- 以独立 Rails Engine `addons/esignatures/`（`Scinote::Esignatures::Engine`，`isolate_namespace`）承载全部电子签名逻辑；**绝不修改核心 `app/`**。
- 数据模型（addon 自有迁移，不碰核心表）：
  - `e_signatures`（策略配置：适用实体列表、是否强制 meaning、是否需二次确认）经 `Extends` 合并注册，禁止改 `config/initializers/extends.rb` 本体。
  - `e_signature_records`（签名事件）：`signable_type`/`signable_id`（多态）、`user_id`、`signed_at`、`meaning`、`record_hash`、`signature_hash`；**无 update/delete 路径**（append-only，应用层不可变）。
- 不可抵赖性靠 `record_hash = H(record 内容 + user_id + signed_at + meaning)`；`signature_hash = H(record_hash + 上一记录 hash)` 形成追加式哈希链（与 0015 审计链可共用原语）。
- 入口不碰核心：核心协议 / 实验页「签名」按钮经 **deface**（`addons/esignatures/app/overrides/*.rb`，`insert_after 'div.content-header'`）注入；`app/decorators/` 仅用于把 `SignatureHelper` 混入 `ApplicationHelper`。
- 核心写路径不变：签名是叠加行为，不修改被签名记录本身，仅读取其当前内容计算哈希。
- 签名服务：`Scinote::Esignatures::SignatureService.call(record:, user:, meaning:)` 生成带时间戳 + 哈希的签名记录，写入不可变存储。
- 验证与导出：提供哈希链完整性校验工具（CLI / rake task）；全量导出时附签名证明（关联 0012 异步导出）。

## Consequences / 风险

- WORM 物理不可篡改超出自托管范围（需 DB / 存储层能力），本 addon 仅在应用层强制不可变，并在导出 / 校验中给出完整性证明；残留风险需 rebase 时复核。
- `engine.rb` 须显式 `config.eager_load_paths << root.join('app', 'permissions')`——引擎 `app/*` 子目录默认不在 `eager_load_paths`，否则 canaid 扫描不到、调用即 `ArgumentError: unknown permission`。
- 迁移初版版本号与核心冲突且不被 Rails 纳入迁移扫描，已改为 `db/migrate/20260901001000_scinote_esignatures_create_tables.rb` 并并入 `db/structure.sql`。
- **单一改动面外溢登记（已知例外）**：迁移直接落在宿主 `db/migrate/`，而非 addon 内 `append_migrations` 模式——属「只收敛进 `addons/esignatures/`」的例外（DB 层外溢）。rebase 上游时须将该文件视为宿主改动点单独核对迁移版本冲突；后续新 addon（如 `ai_eln`）已明确改用 `append_migrations`、**勿复制本特例**。

## 关联

- 0020（addon 配置自声明）
- 0012（异步导出证明）
- `docs/PRODUCT_GAP_AND_PLAN.md`（PRD / 实施进度踩坑）
- `docs/development/addon-dev-workflow.md`
