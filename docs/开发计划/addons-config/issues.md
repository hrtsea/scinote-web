# Issues：Addon 自声明配置机制

> 由 `/to-issues` 拆解，按"纵向切片（tracer bullet）"组织：每个 Issue 独立穿过 schema → API/控制器 → UI → 测试全层。
> 状态图例：**Done**（已实现并通过测试） / **Pending**（待实现）。
> 无可用 issue tracker（GitHub 不可达、无 git/gh CLI），本文件即为可追踪的 Issue 草稿。

---

## Issue 1 — 通用 config-schema 机制（tracer bullet）

**Status**: Done

### What to build
建立 addon 自声明配置机制的骨架：addon 在模块上定义 `self.config_schema` 暴露字段数组；设置页据 `type` 动态渲染类型化控件并据各 addon 自有 locale 显示标签；控制器把表单提交按 schema 类型化写入 `addon_settings.configuration`（JSONB），同时兼容旧的裸 JSON 契约；secret 类字段不回显、留空保留原值。

### Acceptance criteria
- [x] `AddonSetting.config_schema_for(name)` 解析 `Scinote::#{Name}.config_schema`，模块不可达时返回 `[]`。
- [x] 设置页对每个声明 schema 的 addon 渲染类型化控件（boolean/string/integer/secret/text/select）。
- [x] 提交后 `configuration` 按字段类型正确存储（boolean→true/false，integer→整数，secret→保留原值当留空）。
- [x] 仍接受旧裸 JSON 字符串并提交（整体原样存储），不破坏既有数据。
- [x] 未声明 schema 的 addon 仅渲染启用开关。
- [x] secret 字段表单不回显已存值。

### Blocked by
None — 可作为起点立即开始。

---

## Issue 2 — 为三个 addon 播种真实 schema 声明

**Status**: Done

### What to build
为 ai_protocols / esignatures / project_insights 各声明其真实所需的 `config_schema`，并在各自 `config/locales/{en,zh-CN}.yml` 提供标签与帮助文本，使设置页无需改核心代码即可呈现它们的参数。三个 addon 互不依赖，可并行认领（此处按决策合并为单个 Issue）。

### Acceptance criteria
- [x] `Scinote::AiProtocols.config_schema` 含 `parser_url`(string) / `api_key`(secret) / `model`(select，默认 `gpt-4o-mini`)，含 i18n 标签与帮助。
- [x] `Scinote::Esignatures.config_schema` 含 `require_intent`(boolean，默认 true)，并在签名表单 intent 字段的 `required:` 上消费该配置（端到端可见效果）。
- [x] `Scinote::ProjectInsights.config_schema` 含 `default_period_days`(integer，默认 90)。
- [x] 三者的标签/帮助 i18n 键位于各自 addon 的 locale 文件，设置页正确显示中英文。
- [x] 各 schema 形状有 spec 覆盖；设置页渲染三者的字段。

### Blocked by
- Issue 1（依赖通用机制）

---

## Issue 3 —（跟进）ai_protocols 运行时消费配置

**Status**: Done

### What to build
让 ai_protocols 的解析器在运行时实际读取设置页配置：`Scinote::AiProtocols.llm_client` 在 `AddonSetting.configuration` 存在 `parser_url`/`api_key`/`model` 时使用之，否则回退到既有 `ENV['AI_PROTOCOLS_*']` / `ApplicationSettings`。即首轮"仅新增机制、不迁移"决策中显式推迟的部分。配置优先级：显式参数 > AddonSetting 配置 > ENV。

### Acceptance criteria
- [x] ai_protocols 解析时优先取 `AddonSetting.configuration` 中的三项值。
- [x] 当 `AddonSetting` 未配置某项时，正确回退到现有 ENV / ApplicationSettings（行为不变）。
- [x] 未配置任何项的实例，行为与迁移前完全一致（无回归）。
- [x] 该消费路径有 spec 覆盖（配置齐全 / 单项缺失 / 完全缺失三种情形）。

### Blocked by
- Issue 2（依赖 ai_protocols 的 schema 声明）

---

## Issue 4 —（跟进）project_insights 运行时消费 default_period_days

**Status**: Done

### What to build
将 project_insights 在设置页声明的 `default_period_days` 作为瓶颈检测的"陈旧阈值"消费：7/14 天桶不变，`thirty_plus` 桶阈值 = `default_period_days`（默认 90）；UI 标签动态化为 `<N>+ 天`。下钻过滤（current_tasks decorator）与 AggregatorService 使用同一阈值，保证卡片计数与下钻一致。

### Acceptance criteria
- [x] AggregatorService 在配置存在时使用 `default_period_days` 作为 `thirty_plus` 桶阈值。
- [x] 配置缺失时使用既有默认值（90，无回归）。
- [x] 下钻过滤（stale_bucket）与 widget 卡片使用同一阈值。
- [x] 瓶颈 Widget 的 `thirty_plus` 标签动态化为 `<N>+ 天`。
- [x] 该消费路径有 spec 覆盖（默认周期 + 自定义周期）。

### Blocked by
- Issue 2（依赖 project_insights 的 schema 声明）

---

## Issue 5 —（跟进）健壮性与 UX 打磨

**Status**: Done

### What to build
在通用机制之上补强：字段级校验（整数 ≥ 0）、addon 关闭时禁用其参数表单、secret 已存指示（不泄露值）。

### Acceptance criteria
- [x] addon 关闭（`enabled = false`）时，其 schema 字段表单被禁用。
- [x] integer 字段拒绝负值并给出提示（重定向 + alert，不持久化非法值）；必填字符串为空时拦截提交（注：当前 schema 未引入 `required` 标志，该子项作为后续增强）。
- [x] secret 字段在表单显示"已设置"指示（不泄露值）。
- [x] 上述行为有 spec / request spec 覆盖。

### Blocked by
- Issue 1（依赖通用机制）
