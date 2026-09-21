# 0005 — Addon 注册/启用约定（仅 Gemfile 引用，不显式 mount）

## Status

Accepted（2026-09-02，由 i18n addon 实践确认）

## Context

本项目是 SciNote 开源版的自托管二次开发实例，所有扩展均以独立 Rails Engine addon 形式落地于 `addons/<name>/`，模块命名空间以 `Scinote::` 开头（如 `Scinote::AiEln`、`Scinote::Addons::I18n`），以便被 SciNote 的官方扩展点识别。

在 E: 的 SciNote 源码副本里验证脚手架时，曾采用显式 `mount Scinote::Addons::I18n::Engine => '/i18n'` 的装配方式。但在**本仓库（F:\eln\scinote-web-develop）**，既有 addon `ai_eln` 并未在主 `config/routes.rb` 中写任何 `mount` 语句，却依然能正常提供路由与视图——说明本项目的 SciNote 走的是**自动枚举挂载机制**：

- `app/helpers/addons_helper.rb` 的 `list_all_addons` 枚举所有 `Rails::Engine.subclasses` 中以 `Scinote` 开头的引擎；
- 引擎一旦被 `require` 且命名空间以 `Scinote` 开头，即被 SciNote 自动识别并挂载，无需宿主显式 `mount`。

显式 `mount` 属于冗余代码，与本项目既有约定（ai_eln）不一致，且与"零侵入"原则相悖。

## Decision

**新增/注册一个 addon 的标准步骤（宿主侧零修改，路由由 addon 自注册）：**

1. **根 `Gemfile` 引用**（启用开关，仿 `ai_eln` 写法）：
   ```ruby
   # i18n addon (mountable engine, lives in addons/i18n)
   gem 'scinote_addons_i18n', path: 'addons/i18n'
   ```
2. **addon 在自身 `engine.rb` 自注册路由**（零入侵关键：写在 addon 内，宿主 `config/routes.rb` 不动）：
   ```ruby
   # addons/<name>/lib/scinote/<name>/engine.rb
   initializer 'scinote_<name>.routes' do |app|
     app.routes.append do
       mount Scinote::<Name>::Engine => '/'
     end
   end
   ```
   该 initializer 在 boot 期把引擎路由追加进宿主 router 顶层作用域；**不**在主 `config/routes.rb` 写任何 `mount` 行。禁用 addon（注释 Gemfile 行）即不加载引擎、路由不注册、宿主正常启动。详见 `docs/addons-zero-intrusion.md` 第 2 节。
3. **（可选）install 生成器产出宿主 initializer**：
   `rails g scinote:addons:i18n:install` 在宿主 `config/initializers/` 生成可编辑的 `scinote_addons_i18n.rb`（幂等，重跑不覆盖）。

**不做的：**
- 不在宿主 `config/routes.rb` 写 `mount Scinote::<Addon>::Engine => "/..."`（路由自注册由 addon 的 `engine.rb` initializer 完成，宿主零修改）。
- 不改 SciNote 核心 `config/routes.rb` / `config/application.rb` 来枚举引擎。

> 注意：`list_all_addons` 的自动枚举**只识别引擎用于权限/本地化/枚举**，**不会自动挂载路由**。路由可见必须靠 addon 自身的 `routes` initializer（见上第 2 步）。已实测：`ai_eln` 当前 `engine.rb` 缺此 initializer，其 `config/routes.rb` 定义的路由在宿主路由表中为 0 条（不可达），需补上。

## 启用检查清单（每次新增 addon 照此执行）

| 步骤 | 动作 | 验证 |
|------|------|------|
| 生成脚手架 | `rails g addon Scinote::<Addon>`（name 须以 `Scinote` 开头） | `addons/<name>/lib/scinote/<name>/engine.rb` 存在 |
| 修正 gemspec | `rails '~> 4.2.5'` → `'~> 7.2'`、`deface '~> 1.0'` → `'~> 1.9'` | `bundle install` 无版本冲突 |
| Gemfile 引用 | 加 `gem 'scinote_<name>', path: 'addons/<name>'` | `bundle install` 成功 |
| 路由自注册 | addon `engine.rb` 加 `initializer 'scinote_<name>.routes' { app.routes.append { mount Engine => '/' } }` | `rails runner` 查路由表含 addon 控制器 |
| 验证枚举 | `rails runner "Rails::Engine.subclasses.select{|c|c.name.to_s.start_with?('Scinote')}.map(&:module_parent).map(&:name)"` | 输出含 `Scinote::<Addon>` |

## Consequences

- 所有 addon 装配方式统一，降低维护认知负担；宿主受管文件仅 `Gemfile` 一行启用开关。
- 升级 SciNote 时只要官方的自动枚举 + `app.routes.append` 机制稳定，宿主装配代码无需改动。
- 修正了此前"本项目完全无需 mount"的误判：宿主 `routes.rb` 确实无需 mount（零入侵），但 addon 必须在自身 `engine.rb` 自注册路由，否则路由不可达。
