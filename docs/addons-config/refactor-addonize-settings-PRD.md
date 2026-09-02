# PRD：Addon 设置页逻辑 addon 化（从核心 app/ 抽离）

> 来源：基于提交 `ab46c68c8`（feat: generic per-addon settings config mechanism）对 addons 设置页的探查。该提交把「addon 自声明配置」机制的 UI/控制器/helper 直接落在核心 `app/` + `config/`（7 个 M + 11 个 A），违反铁律「绝不直接编辑核心 app/」。本 PRD 将其**重构为独立 addon**，使「设置页本身也实现为 addons」。
> 前置已完成：`docs/addons-config/PRD.md` + `issues.md`（config_schema 机制，Issues #1–#5 全部 Done）。本 PRD 是**把已落地的核心代码 addon 化**，不重复发明机制。
> 仓库 ADR 单一存放处：`docs/ARCHITECTURE_DECISIONS.md`（ADR-013 为本机制）。本重构落地后需在 ADR-013 增补「设置页 UI 已 addon 化、底座留核心」的收尾说明。

## 4 个 Grill 决策（已确认，待你核对）
> 以下为规划前的 grill 结论。若任一与你的记忆不符，告知我即据以修正 Issues 拆分。

- **D1 — 设置页 UI 封装为独立 addon `addons/addon_settings`**：`addons_controller.rb`(index)、`addons/index.html.erb`、`addons_helper.rb`(render_addon_config_field/input)、`config/locales/*` 的 `users.settings.account.addons.*` 键，整体搬进该 addon（engine 内实现 + 自注册路由）。不并入任何业务 addon（ai_protocols/esignatures/project_insights），因设置页是横切「宿主」。
- **D2 — AddonSetting 模型 + 迁移留在核心**：它是 config_schema 机制的运行时底座，各业务 addon 经 `AddonSetting.config_schema_for(name)` 暴露 schema；搬进 addon 会引入加载顺序/循环依赖（鸡生蛋）。明确为「有意为之的例外」。
- **D3 — update_addon 路由自注册**：从 `config/routes.rb` 删除 `put .../addons/:name`，改由 `addons/addon_settings/engine.rb` 的 initializer 自注册（符合铁律「主 routes.rb 不含 addon 路由」）；卸载该 addon 时主程序零改动。
- **D4 — InstanceAdmin 权限（:manage_addons）留在核心**：跨 addon 实例级权限，是基础设施；设置页 addon 经 `can_manage_addons?` 消费它。搬进 addon 会让核心安全门控反向依赖 addon，违反方向。

## Problem Statement

实例管理员在统一设置页（`/users/settings/account/addons`）开启/关闭每个 addon 并填写参数。批 4 已实现该能力，但实现直接写在核心 `app/controllers/.../addons_controller.rb`、`app/views/.../index.html.erb`、`app/helpers/addons_helper.rb`、`config/routes.rb`、`config/locales/*`——违反铁律。后果：将来 rebase 上游时，这些散落在核心的设置页代码成为额外冲突面；且「配置参数页面也应实现为 addons」的诉求未彻底贯彻。

## Solution

把设置页逻辑抽成独立 addon `addons/addon_settings`（承载页面 UI、字段渲染 helper、locale 键、自注册路由），使其符合铁律的「单一改动面」。AddonSetting 模型/迁移/InstanceAdmin 权限作为「底座」留核心（D2/D4 鸡生蛋例外）。重构后行为完全不变，但核心 `app/` 不再含设置页业务代码。

## User Stories

1. As an 实例管理员, I want 设置页照常显示每个 addon 的开关与类型化配置表单, so that 我的使用体验不变（重构透明）。
2. As an 实例管理员, I want 提交配置后仍被类型化保存、secret 不回显、整数≥0 校验、关闭时禁用表单, so that 机制行为不变。
3. As an 维护者, I want 设置页代码全部位于 `addons/addon_settings/`, so that rebase 上游冲突面最小化（铁律）。
4. As an 维护者, I want 卸载 `addons/addon_settings` 时主程序零改动（仅撤 Gemfile 一行）, so that 它是可插拔的。
5. As an addon 开发者, I want `AddonSetting.config_schema_for` 与 `can_manage_addons?` 仍从核心可用, so that 我的 addon 不需改任何代码即可继续工作（底座稳定）。

## Implementation Decisions

- **承载 addon**：`addons/addon_settings/`（`Scinote::AddonSettings::Engine`，`isolate_namespace`），含 `app/controllers/users/settings/account/addons_controller.rb`（index/update）、`app/views/.../index.html.erb`、`app/helpers/addons_helper.rb`、`app/config/locales/{en,zh-CN}.yml`、`engine.rb`（initializer 自注册 `addons_path` GET + `update_addon_path` PUT）。
- **自注册路由（D3）**：`engine.rb` 内 `initializer 'scinote_addon_settings.routes' do |app| app.routes.append do ... end end`；核心 `config/routes.rb` 删除 `addons` GET 与 `update_addon` PUT 两行。
- **底座留核心（D2/D4）**：`app/models/addon_setting.rb` + `db/migrate/20260901130000_create_addon_settings.rb` + `app/permissions/instance_admin.rb` + `app/services/instance_admin.rb` 保留在核心；设置页 addon 经 `can_manage_addons?` 消费权限、`AddonSetting.*` 消费模型。
- **权限消费**：addon 内 `authorize_addon_admin!` 仍调用核心 `can_manage_addons?`，不满足 `render_403`。
- **locale 归属（D1）**：`users.settings.account.addons.*` 键随 UI 进 addon 自有 locale（引擎自动加载），从核心 `config/locales` 删除，不污染核心。
- **decorator vs 直接实现**：设置页是**整页 owned by addon**，直接由 addon 的 controller/view 实现（无需 decorator 覆盖核心页），核心删除对应文件即可。

## Testing Decisions

- 只测外部行为、行为与重构前逐字节等价：GET 设置页渲染所有 addon 开关+字段、类型化控件正确；PUT 提交类型化保存、secret 不回显、整数≥0 校验、禁用态；卸载 addon 后核心启动正常（仅撤 Gemfile）。
- 复用既有 `spec/requests/users/settings/account/addons_spec.rb`（迁到 `addons/addon_settings/spec/`）；补充「路由自注册 / 卸载零改动」测试。
- 业务 addon（ai_protocols/esignatures/project_insights）的 config_schema 消费测试保持绿，证明底座未动。

## Out of Scope

- 改动 config_schema 机制本身（已由已完成 PRD 覆盖，本重构只搬代码位置）。
- 新增设置页功能（分组/富 UI/搜索）。
- 团队级配置覆盖（实例级 `AddonSetting` 不变）。
- 把 AddonSetting 模型/迁移/权限也搬进 addon（D2/D4 明确不搬）。

## Further Notes / ADR

- 落地后在 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-013 增补：「设置页 UI 已 addon 化于 `addons/addon_settings`；AddonSetting 模型/迁移/InstanceAdmin 权限作为底座留核心（鸡生蛋例外，非铁律违反）」。
- 更新 `docs/agents/addon-dev-workflow.md` 检查清单：新增「设置页逻辑位于 `addons/addon_settings`，核心不含设置页业务代码」。
- 风险：`AddonSetting.config_schema_for` 必须持续安全降级（模块不可达返 `[]`），否则未声明 addon 的页面渲染报错——此约束不因 addon 化而改变。
