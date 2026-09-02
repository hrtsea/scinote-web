# Issues：Addon 设置页逻辑 addon 化

> 由 `/to-issues` 拆解，按「之前 4 个 Grill 决策」（D1–D4）组织为 4 个纵向切片。每个 Issue 独立可交付、穿过全层。
> 前置：已完成 config_schema 机制（`docs/addons-config/issues.md` #1–#5 Done）。
> 决策对照：D1→Issue 1、D3→Issue 2、D2→Issue 3、D4→Issue 4。

---

## Issue 1（D1）— 抽取设置页进 `addons/addon_settings`

**Status**: ✅ Done（已验证 `bundle exec rspec` 12 examples, 0 failures）

### What was built
新建 `addons/addon_settings` Rails 引擎，把**整个 `Users::Settings::Account::AddonsController`（index + update）**搬入 addon；view、`Scinote::AddonSettings::AddonsHelper`（render 方法）、locale（`users.settings.account.addons.*`）一并迁入；addon 自注册 GET `addons_path` 与 PUT `update_addon` 路由（后者见 Issue 2）。Gemfile 一行 `gem 'scinote_addon_settings', path: 'addons/addon_settings'`。

### 偏差（重要，影响 Issue 2 范围）
原 D1 设想「仅搬 index、update 留核心到 Issue 2」。但核心 `app/controllers/.../addons_controller.rb` 与 addon 内同名 `Users::Settings::Account::AddonsController` 是**同一常量**，Zeitwerk 不允许两个文件定义它。因此**核心 controller 文件被整体删除**，update 逻辑一并迁入 addon。结果是：Issue 2 仅剩「把 `update_addon` PUT 路由自注册从核心 routes.rb 迁到 addon engine」这一纯路由动作，无 controller 代码搬运。

### Acceptance criteria
- [x] `addons/addon_settings` 引擎可加载（顶层 `lib/scinote_addon_settings.rb` 入口 + `isolate_namespace` + Gemfile 一行）。
- [x] GET `/users/settings/account/addons` 由 addon 渲染，显示所有 addon 开关 + 类型化字段，中英文正确。
- [x] 核心 `app/controllers/.../addons_controller.rb`（整体）、`app/views/.../index.html.erb`、`app/helpers/addons_helper.rb`（render 方法）均删除；核心 locale `account.addons.*` 段删除（helper 的 `list_all_addons` 保留，被 `config/initializers/load_addons_specs.rb` 依赖）。
- [x] 卸载 addon（撤 Gemfile 一行）后主程序启动正常（路由未注册即 404，无崩溃）。
- [x] spec 覆盖（迁自核心，GET + PUT 共 12 例全绿）。

---

## Issue 2（D3）— `update_addon` PUT 路由自注册进 addon

**Status**: ✅ Done（验证 `12 examples, 0 failures`；rails routes 确认核心 `config/routes.rb` 不再含 addons/update_addon 行）

### What was built
`update_addon` PUT 路由从核心 `config/routes.rb` 删除，改由 addon `engine.rb` initializer 的 `app.routes.append` 块自注册（与 GET 同块）。controller 的 `update` action 已在 Issue 1 迁入 addon，本 Issue 无 controller 代码搬运。

### Acceptance criteria
- [x] PUT `/users/settings/account/addons/:name` 由 addon 处理（类型化保存、secret 留空保留、整数≥0 校验、关闭时禁用逻辑生效）——由迁来的 spec 覆盖。
- [x] 核心 `config/routes.rb` 无 `update_addon`、无 `addons` GET（均已迁到 addon engine）。
- [x] 卸载 addon 后主程序启动正常（PUT 路由未注册即 404）。

### Blocked by
- Issue 1

---

## Issue 3（D2）— AddonSetting 模型/迁移底座化（留核心）

**Status**: ✅ Done（验证：业务 addon config_schema/enabled 契约 spec 10 examples 0 failures；addon_settings GET spec 端到端覆盖 config_schema 消费；AddonSetting 模型/迁移未动）

### What to build
确认 `app/models/addon_setting.rb` + `db/migrate/20260901130000_create_addon_settings.rb` 留在核心（不搬）；补 ADR-013 说明「模型/迁移为底座、鸡生蛋例外」；验证三个业务 addon 的 config_schema 消费测试不受影响（`AddonSetting.config_schema_for` 行为不变）。

### Acceptance criteria
- [x] 业务 addon（ai_protocols/esignatures/project_insights）的 config_schema 相关测试全绿（跑 `enabled_spec`/`ai_protocols_spec`/`registration_spec`：10 examples 0 failures）。
- [x] `AddonSetting.enabled?`/`for`/`config_schema_for`/`config_value` 行为不变（模型 `app/models/addon_setting.rb` 与迁移 `20260901130000_create_addon_settings.rb` 未动）。
- [x] ADR-013 增补底座说明（见 `docs/ARCHITECTURE_DECISIONS.md` ADR-013 收尾段）。

### Blocked by
- Issue 1（需先确认 UI 抽离后仍正确消费核心 `AddonSetting`）

---

## Issue 4（D4）— InstanceAdmin 权限底座化 + 收口回归

**Status**: Pending

### What to build
确认 `app/permissions/instance_admin.rb` + `app/services/instance_admin.rb`（`:manage_addons` 权限）留在核心；收口——`rubocop`+`brakeman`+`rspec` 全绿（含业务 addon 测试）、更新 `docs/agents/addon-dev-workflow.md` 检查清单（新增设置页 addon 化条目）、ADR-013 收尾。

### Acceptance criteria
- [ ] 核心 `app/` 仅剩底座文件（AddonSetting 模型、instance_admin 权限/服务、迁移）；无设置页业务代码。
- [ ] `rubocop addons/addon_settings` + `brakeman` + `rspec`（含 `spec/addons/addon_settings` 与业务 addon 测试）全绿。
- [ ] `addon-dev-workflow.md` 检查清单新增「设置页逻辑位于 `addons/addon_settings`」。
- [ ] ADR-013 标注「设置页 UI 已 addon 化，底座留核心」。

### Blocked by
- Issue 2、Issue 3
