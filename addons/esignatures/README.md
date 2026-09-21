# scinote_esignatures

SciNote 电子签名 addon（21 CFR Part 11 合规）。以独立 Rails Engine 实现，
**不修改核心 `app/`**。

## 能力
- 对协议（Protocol）/ 结果（Result）/ 实验（Experiment）发起电子签名。
- 签名记录：签名人、时间戳、意图声明（meaning），与目标记录强绑定、不可篡改。
- 追加式哈希链（`previous_hash` → `signature_hash`），保证签名序列不可抵赖。
- 应用层不可变：签名记录无 update/delete 路径。

## 扩展点（遵循 docs/development/addon-dev-workflow.md）
- 引擎：`Scinote::Esignatures::Engine`，`isolate_namespace`。
- 权限：`app/permissions/**/*.rb`，由 `config/initializers/canaid.rb` 自动发现。注意：引擎 `app/*` 子目录默认不在 `config.eager_load_paths`，canaid 扫描不到，故 `engine.rb` 已显式 `config.eager_load_paths << root.join('app', 'permissions')`——否则调用 `can_sign_*_record?` 会抛 `ArgumentError: unknown permission`。
- 入口（签名按钮）：核心 `protocols/_header` 与 `experiments/_show_header` 是服务器渲染的 header，经 **deface**（`app/overrides/*.rb`）`insert_after 'div.content-header'` 注入 `signature_panel_for` 面板，不碰核心视图；`signature_panel_for` 自身用 `can_sign_record?` 门控，无权限返回空串。`app/decorators/application_helper_decorator.rb` 仅把 `SignatureHelper` 混入 `ApplicationHelper` 供面板渲染。结果（Result）签名落在 Vue canvas 内，需 JS 入口，留作后续。
- 配置（适用实体/是否强制 meaning）：经 `Extends` 合并，不改动 `extends.rb` 本体。
- 迁移：`e_signatures` / `e_signature_records` 两表的迁移按 Rails 引擎惯例**安装到宿主 `db/migrate`**（`20260901001000_scinote_esignatures_create_tables.rb`），而非留在 addon 内——Rails 不会自动把引擎 `db/migrate` 纳入 `db:migrate` 扫描路径，留在 addon 内会导致 `db:migrate:status` 报 `NO FILE` 且新库无法建表。

## 开发
见 `docs/PRODUCT_GAP_AND_PLAN.md`（Addon A / G1）与 `docs/ARCHITECTURE_DECISIONS.md`（ADR-007）。
