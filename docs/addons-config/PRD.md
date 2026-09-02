# PRD：Addon 自声明配置机制（设置页开启 + 参数）

> 来源：`/to-issues` 拆解前的综合文档。本特性已实现核心机制与三个 addon 的 schema 声明（见 Issues #1、#2，状态 Done），并规划了运行时消费与打磨跟进（#3、#4、#5，状态 Pending）。
> 仓库 ADR 单一存放处为 `docs/ARCHITECTURE_DECISIONS.md`；本特性相关决策将在落地后补 ADR（见"进一步说明"）。

## Problem Statement

实例管理员需要在统一的设置页（`/users/settings/account/addons`）开启/关闭每个 addon，并填写该 addon 所需的配置参数（如 AI 解析器的 URL/密钥/模型、电子签名的必填意图开关、项目洞察的默认周期）。当前 `AddonSetting#configuration` 是**自由 JSON**，设置页用**裸 `text_area` 手填 JSON**——无结构、无类型、无各 addon 自描述。每个新 addon 的参数都要改设置页/模型硬编码，违背"配置参数页面也应**实现为 addons**"的诉求：addon 应当**自治地把自己需要的配置项暴露到设置页**。

## Solution

建立"addon 自声明 `config_schema`"的通用机制：

- 每个 addon 在其模块上定义 `self.config_schema`，返回字段数组（每个字段含 `key` / `label` / `type` / `default` / 可选 `options` / `help`）。
- 设置页读取 `AddonSetting.config_schema_for(name)`，按 `type`（boolean / string / integer / secret / text / select）动态渲染类型化控件，并据各 addon 自有 `config/locales` 的 i18n 键显示标签与帮助文本。
- 提交时 `AddonsController#cast_configuration` 按 schema 把表单值**类型化**写入 `addon_settings.configuration`（JSONB），并兼容旧的裸 JSON 契约。
- secret 类字段不在表单回显，留空时保留原值。

这样"配置参数页面"本身由各 addon 以 schema 形式实现——正是"实现为 addons"的落地。

## User Stories

1. As an 实例管理员, I want 在统一设置页看到每个已挂载 addon 的开/关开关, so that 我能逐 addon 控制功能启用。
2. As an 实例管理员, I want 设置页按每个 addon 自声明的结构渲染参数表单（含类型、标签、帮助文本）, so that 我无需手填 JSON 即可正确配置。
3. As an 实例管理员, I want 文本框/数字框/下拉框/勾选框按字段类型正确呈现与保存, so that 配置值类型可靠。
4. As an 实例管理员, I want 密钥类字段不在页面回显且留空即保留原值, so that 密钥不会因误提交而清空或泄露。
5. As an 实例管理员, I want 提交非法配置时被拦截并收到错误提示, so that 不会写入损坏配置。
6. As an addon 开发者, I want 用 `config_schema` 一个方法声明我的配置项（含类型与默认值）, so that 设置页自动渲染，我无需改核心代码。
7. As an addon 开发者, I want 我的配置标签/帮助文本放在 addon 自有 `config/locales`, so that 国际化自洽、不污染核心 locale。
8. As an 实例管理员, I want 为 ai_protocols 配置解析器 URL、API Key、模型, so that AI 协议解析按实例设定工作。
9. As an 实例管理员, I want 为 esignatures 配置"是否强制签名意图"开关, so that 签名流程可按需要求填写意图。
10. As an 实例管理员, I want 为 project_insights 配置默认聚合周期（天数）, so that 看板洞察的默认时间窗口可配。
11. As an 实例管理员, I want ai_protocols 实际消费我在设置页填的解析器/密钥/模型（回退到现有 ENV）, so that 配置真正生效。
12. As an 实例管理员, I want project_insights 用我配置的默认周期作为聚合窗口, so that 洞察默认范围与配置一致。
13. As an 实例管理员, I want addon 关闭时其参数表单被禁用, so that 不会在禁用状态下误配。
14. As an 实例管理员, I want 字段级校验（如整数 ≥ 0、必填项）, so that 配置健壮性更强。

## Implementation Decisions

- **模块 / 接口（已落地）**
  - `AddonSetting`（`app/models/addon_setting.rb`）：新增 `self.config_schema_for(name)`（解析 `Scinote::#{Name}.config_schema`，不可达时返回 `[]`）；既有 `self.enabled?` / `self.for` / `config_value` 复用。
  - `Users::Settings::Account::AddonsController`（`app/controllers/.../addons_controller.rb`）：新增 `cast_configuration(name, raw)`，按 schema 把 `configuration[key]=value` 类型化；兼容裸 JSON 字符串（整体原样存储）。
  - `AddonsHelper`（`app/helpers/addons_helper.rb`）：`render_addon_config_field` / `render_addon_config_input` 按 `type` 分派控件（checkbox / password / number / textarea / select / text）。
  - 视图 `app/views/users/settings/account/addons/index.html.erb`：在 addon 卡片内对 `config_schema_for(name)` 循环渲染字段。
  - 各 addon：`Scinote::AiProtocols.config_schema`、`Scinote::Esignatures.config_schema`、`Scinote::ProjectInsights.config_schema`（字段含 i18n label/help 键，置于 addon 自有 `config/locales/{en,zh-CN}.yml`）。
- **约定**：addon 模块定义 `self.config_schema` 返回 `[{ key:, label:, type:, default?, options?, help? }]`；未声明则返回 `[]`，设置页仅渲染启用开关。
- **显式不迁移（本特性首轮决策）**：ai_protocols 既有从 `ENV['AI_PROTOCOLS_*']` / `ApplicationSettings` 读取的逻辑保持不变；新机制只"新增"暴露入口，运行时尚不强制改用 `AddonSetting`（见 Issue #3）。
- **类型契约**：`type ∈ {boolean, string, integer, secret, text, select}`；`select` 需 `options: [{label:, value:}]`。
- **i18n**：标签/帮助键在各 addon 自有 locale（引擎自动加载），不写入核心 `config/locales`。

## Testing Decisions

- **好测试的标准**：只测外部行为——提交表单后 `addon_settings.configuration` 的类型化结果、schema 缺失时仅渲染开关、secret 不回显且留空保留、旧裸 JSON 仍被接受。不测内部 `case/when` 分支细节。
- **被覆盖模块**：`AddonSetting`（schema 解析、enabled? 契约）、`AddonsController`（cast_configuration 类型化与兼容）、`AddonsHelper`（各 type 渲染）、视图（schema 循环渲染）、各 addon 的 `config_schema` 形状。
- **既有先例**：addon 相关测试沿用 `spec/` 下 request/helper/view spec；本次已补 31 个用例覆盖上述路径。

## Out of Scope

- 迁移 ai_protocols 既有 ENV/ApplicationSettings 读取逻辑到新机制（首轮仅新增机制，不迁移；消费跟进见 #3）。
- 多租户/团队级配置覆盖（本机制为实例级 `AddonSetting`）。
- 新增更多 addon（除 ai_protocols / esignatures / project_insights 外的其他 addon 声明）不在此列，按同一 `config_schema` 约定后续自行声明即可。
- 配置项的分组/分区、富 UI（如可折叠分节、搜索）。

## Further Notes

- **ADR 建议**：本特性确认了"addon 自治暴露配置"范式。落地后建议在 `docs/ARCHITECTURE_DECISIONS.md` 新增 ADR（编号待定），记录：schema 约定、不迁移既有配置源的决策、secret 不回显约定。
- **运行时消费的前提**：Issue #3/#4 触发时，需确认从 `AddonSetting.configuration` 读取与既有 ENV 回退的优先级，避免破坏现有部署（已用 ENV 的环境不应被空配置覆盖）。
- **复用**：三个 addon 共用同一 `config_schema_for` + helper 渲染机制，无需重复接线。
