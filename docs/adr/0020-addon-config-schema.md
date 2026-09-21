# 0020 — Addon 配置自声明机制（设置页开启 + 参数，由各 addon 以 schema 自治暴露）

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-013（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（核心机制 + 三 addon 播种 schema 已实现并通过测试）

## Context

用户诉求「addon 配置项应明确反映在设置页，addon 需有机制把自身所需设置项目暴露到 addon 设置页」；代码库现状为 `AddonSetting#configuration` 是**自由 JSON**，设置页用**裸 `text_area` 手填 JSON**——无结构、无类型、无各 addon 自描述，每新增 addon 参数都要改设置页 / 模型硬编码。

## Decision

建立 "addon 自声明 `config_schema`" 的通用机制，**绝不修改核心 `app/` 来逐个 addon 硬编码字段**：

- **自治暴露（核心范式）**：每个 addon 在其模块上定义 `self.config_schema`，返回字段数组（每字段含 `key` / `label` / `type` / `default?` / `options?` / `help?`）；设置页读取 `AddonSetting.config_schema_for(name)`（`Scinote::#{Name}.config_schema`，模块不可达时安全返回 `[]`，此时仅渲染启用开关），按 `type` 动态渲染类型化控件，并据各 addon 自有 `config/locales` 的 i18n 键显示标签 / 帮助。
- **类型契约**：`type ∈ {boolean, string, integer, secret, text, select}`；`select` 需 `options: [{label:, value:}]`；`AddonsController#typed_configuration` 提交时按字段类型化写入 `addon_settings.configuration`（JSONB）。
- **仅新增机制，不迁移既有配置源**：ai_protocols 既有从 `ENV['AI_PROTOCOLS_*']` / `ApplicationSettings` 读取的逻辑保持不变；新机制只"新增"暴露入口，运行时尚不强制改用 `AddonSetting`。
- **secret 约定**：secret 类字段不在表单回显，留空即保留原值。
- **i18n 自洽**：标签 / 帮助键置于各 addon 自有 `config/locales/{en,zh-CN}.yml`，不写入核心 locale。
- **兼容旧契约**：`typed_configuration` 仍接受裸 JSON 字符串（整体原样存储），不破坏既有数据。

## Consequences / 风险

- 若某 addon 声明了 schema 但运行时尚未消费（如 ai_protocols 已声明 `parser_url`/`api_key`/`model`，但首轮仅暴露未消费），则设置页可填但暂未生效——该缺口由 Issue #3（ai_protocols）与 #4（project_insights `default_period_days`）跟进补齐。
- 核心 `AddonSetting#config_schema_for` 必须持续保证**安全降级**（模块不可达返回 `[]`），否则未声明 addon 的设置页渲染会报错。
- 本机制为实例级（`AddonSetting`），不涉及团队级覆盖。

## 关联

- 0013（ai_protocols 已声明 schema，运行时经 `Scinote::AiProtocols.llm_client` 消费配置，回退 ENV）
- 0015（project_insights `default_period_days` 作为瓶颈陈旧阈值）
- 0022（addon 路由自注册 / 设置页 addon 化收尾）
- `docs/开发计划/addons-config/PRD.md`、`docs/开发计划/addons-config/issues.md`、`docs/development/addon-dev-workflow.md`

> 设置页 addon 化收尾（2026-09-02）：设置页 UI（controller/view/helper/locale）已抽离至 `addons/addon_settings` 引擎。`AddonSetting` 模型（`addons/addon_settings/app/models/addon_setting.rb`）与 `20260901130000_create_addon_settings` 迁移作为该引擎的**自包含底座**一并随引擎落地，经 `append_migrations` 注入宿主 `db/migrate`；`InstanceAdmin` 权限/服务仍留核心 `app/`。引擎声明 `isolate_namespace Scinote::AddonSettings`，经自身 `config/routes.rb`（含 `as: :update_addon` 等）自挂载路由，宿主 `addons_path`/`update_addon_path` 等 helper 经 `config.to_prepare` 提升到宿主级（见 0022），核心 `config/routes.rb` 不再含设置页路由。
