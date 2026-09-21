# 0022 — Addon 路由自注册统一策略（engine initializer 自挂载，host 零修改）

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-016（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（2026-09-02）

## Context

核对「高级：initializer 注入 mount，实现 application.rb 零字符修改」文档说法，确认项目在「零入侵」目标上与文档一致、具体配方有分歧，并统一 `addon_settings` 的路由注册机制。

## Decision（统一契约）

1. **全部 addon 路由均由各自 `engine.rb` 的 initializer 自注册**：
   `initializer 'scinote_<name>.routes', after: :add_routes do |app| app.routes.append { mount <Engine> => <mount_point> } end`；核心 `config/routes.rb` 与 `application.rb` 零 addon 路由 / 配置，仅 Gemfile 一行引入即生效、注释即禁用（启动正常，路由未注册即 404，无崩溃）。
2. **「统一」统一的是机制，不是挂载路径**：所有 addon 走**同一套机制**——由各自 `engine.rb` 的 initializer 自挂载 `mount <Engine>`，且经 `after: :add_routes` 追加到宿主路由之后；host 的 `config/routes.rb` / `application.rb` 零侵入。至于「挂载到哪」（`mount_point`）是**各 addon 的本地决策，按 UX 场景而定**，不必强求一致：现状既有挂根 `'/'` 的（project_insights / ai_protocols / esignatures / addon_settings），也有挂宿主既有前缀的（i18n locale 挂到 `/users/settings/locale`）。**统一契约 = "都是 `mount Engine`"，不是"都挂到同一路径"**。
3. **`addon_settings` 由「裸 `app.routes.append { get/put }`」改造为正规挂载引擎**：新增 `config/routes.rb` 承载其 host 风格路由，并**保留 `isolate_namespace Scinote::AddonSettings`**。其控制器已扁平化为 `Scinote::AddonSettings::AddonsController`；宿主 20+ 处直接引用的 `addons_path` / `update_addon_path` 之所以在隔离后仍可用，是依靠 `engine.rb` 的 `config.to_prepare` 把这两个 helper 提升（promote）到宿主级，而非保留宿主命名空间。
4. **时序统一 `after: :add_routes`**：显式、防御性、与文档对齐；在 Rails 7.2.3.2 下 `app.routes.append` 不依赖该顺序也能工作，但显式声明规避潜在坑。

## 避撞规则（硬约束）

每个 addon 必须独占一个唯一根路径前缀（现状已满足：`/insights`、`/ai_protocols`、`/esignatures/sign`、`/users/settings/locale`、`/users/settings/account/addons`）。因 addon 路由经 `after: :add_routes` 追加在**宿主路由之后**，若与宿主或他 addon 同路径同动词，宿主优先匹配 → addon 静默 404（路由遮蔽）。新增 addon 须先校验路径不与既有冲突。

## 升级路径

若未来引入第三方 / 社区 addon 或路径重叠风险升高，改用子路径挂载 `mount <Engine> => '/<addon>'`（引擎内路由相应改为根路径，对外 URL 基本不变），以彻底隔离命名空间。当前 curated 规模（5 个 addon）下根挂载可接受。

## Consequences / 风险

- 根挂载共享根命名空间，碰撞靠「唯一前缀约定」而非结构保障（脆弱现状）；升级路径见上。
- 各 addon 覆盖点（deface / decorator）仍须随上游演进复核（沿用 0013~0021 冲突提示）。

## 关联

- 0020（addon 配置自声明 / 设置页 addon 化）
- 0013 / 0014 / 0015 / 0016（各 addon 实现）
- 0005（addon 注册约定）
- `docs/development/addon-dev-workflow.md`
