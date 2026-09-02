# Addon 宿主契约（Host ↔ Addon Contract）

> 本文是 SciNote addon 机制的**契约规格 / 总索引**，描述「宿主（`scinote-web` 主应用）向 addon 保证什么、addon 必须履行什么」。
> 配套文档（避免重复，深入细节请跳转）：
> - `addon-generator.md` —— 生成器 `lib/generators/addon` 的内部实现与目录产出。
> - `addons-zero-intrusion.md` —— 以路由为重点的零入侵自注册机制叙事。
> 本文聚焦：**发现机制（反射）、命名双轨、全接缝对照表、强制位置、契约偏差与最小合规清单**。

---

## 1. 契约速览（双方义务）

| 角色 | 义务 / 保证 |
|---|---|
| **宿主** | ① 经由 `Bundler.require` 加载 `addons/*` 下被启用的 gem；② 反射发现所有 `Scinote::*` 引擎；③ 提供通用（`addons/*` 通配）接缝：autoload 排除、i18n、权限、测试软链、迁移追加；④ 禁用 addon（注释 Gemfile 行）时**仍能正常启动**。 |
| **addon** | ① 是 `Scinote::` 前缀的 `Rails::Engine`；② 落在 `addons/<addon_name>/`；③ 在 `Gemfile` 以 `gem '<full_underscore_name>', path: 'addons/<addon_name>'` 注册为启用开关；④ 能力通过引擎 `initializer`/`to_prepare` 自注册（不修改宿主 `app/`、`config/routes.rb` 等受管文件）。 |

---

## 2. 发现机制（反射）—— 契约入口

addon 不是被宿主「列举」的，而是被「反射」发现的。链路如下：

1. `config/application.rb:22` —— `Bundler.require(*Rails.groups)` 加载所有在 `Gemfile` 中启用的 gem。
2. 被启用的 addon gem（如 `scinote_project_insights`）其 `lib/scinote_project_insights.rb`（`gemspec` 主文件）执行 `require 'scinote/project_insights'; require 'scinote/project_insights/engine'`（`addon_generator.rb:144-149` 生成的垫片）。
3. `require .../engine` 触发 `Scinote::ProjectInsights::Engine < ::Rails::Engine` 类定义。
4. 该类进入 `Rails::Engine.subclasses`，被 `list_all_addons` 反射收集：
   ```ruby
   # app/helpers/addons_helper.rb:6-11
   def list_all_addons
     Rails::Engine.subclasses
       .select { |c| c.name.start_with?('Scinote') }
       .map(&:module_parent)
   end
   ```
5. 大量宿主设施据此消费 addon：`config/initializers/canaid.rb:9-18`（权限目录扫描）、`config/initializers/load_addons_specs.rb:11-16,22-27`（测试/feature 软链）、`addons-zero-intrusion.md` 的路由自挂载。

> **契约要点**：addon 的引擎类**必须**以 `Scinote` 开头（`select { ...start_with?('Scinote') }`），否则不会被发现。生成器强制 `NAME` 形如 `Scinote::X`（`addon-generator.md` §2），正是为了满足此反射过滤。

---

## 3. 命名双轨契约（关键，最易被坑）

生成器把 `NAME`（如 `Scinote::ProjectInsights`）拆成三套派生名（`addon_generator.rb:5-11`），三者**用途各不相同**：

| 派生名 | 计算 | 例子 | 用在哪 |
|---|---|---|---|
| 模块名 `NAME` | 原样 | `Scinote::ProjectInsights` | 引擎类、`isolate_namespace`、权限/命名空间 |
| gem 名 `full_underscore_name` | `folders.join('_')` | `scinote_project_insights` | **Gemfile `gem` 名**、`gemspec` name、`lib/<gem>.rb` 主文件 |
| 目录名 `addon_name` | `folders[-1]` | `project_insights` | **物理目录 `addons/<addon_name>/`**、引擎 `load_localization` 路径 |

由此推出**唯一的合规启用写法**（与 `Gemfile:143-147` 完全一致）：

```ruby
gem 'scinote_project_insights', path: 'addons/project_insights'
#    ^gem 名(双下划线)            ^目录名(最后一段)
```

> 若写成 `gem 'project_insights', ...` 或 `path: 'addons/scinote_project_insights'` 都会错配——Bundler.require 的 gem 名与磁盘目录由两套不同派生名决定。

---

## 4. 强制位置契约（路径写死进引擎）

引擎模板 `lib/generators/addon/templates/engine.rb:22-32` 的 `load_localization` initializer **硬编码**宿主根下的 addon 位置：

```ruby
app.config.i18n.load_path += Dir[
  Rails.root.join('addons', '${ADDON_NAME}', 'config', 'locales', '*.{rb,yml}')
]
```

即引擎假定自身一定位于 **`Rails.root/addons/<addon_name>/`**。这与 `Gemfile` 的 `path: 'addons/<addon_name>'` 互为对齐——离开这个位置，i18n 文件将不会被加载（且不报错的静默失效）。这是契约的「物理锚点」。

---

## 5. 全接缝对照表（宿主 ↔ 生成器 ↔ addon 义务）

| 接缝（能力） | 宿主侧依据（file:line） | 生成器/模板提供 | addon 需履行的义务 |
|---|---|---|---|
| **发现** | `application.rb:22`、`addons_helper.rb:6-11`、`canaid.rb:9-19` | `lib/<gem>.rb` 垫片（`addon_generator.rb:144-149`）+ 引擎类 | 引擎类以 `Scinote::` 开头；gemspec `s.name` = `full_underscore_name` |
| **启用开关** | `Gemfile:143-147` | `.gemspec`（name=gem 名） | 在 `Gemfile` 加 `gem '<gem>', path: 'addons/<dir>'` |
| **路由自挂载** | `routes.rb:14-17`（无 mount 行）、`addons-zero-intrusion.md` | `engine.rb` 的 `*.routes` initializer（`after: :add_routes`，`app.routes.append { mount ... }`） | 用 `Engine.routes.draw do … end` 定义路由；**不**改宿主 `routes.rb` |
| **i18n** | `engine.rb:22-32` 硬编码 `addons/<addon_name>/config/locales` | 生成 `config/locales/en.yml` | 翻译文件置于 `config/locales/`，无需改宿主 |
| **权限（canaid）** | `canaid.rb:5,8-19`（`permissions_paths <<` + 扫描 `app/permissions`） | （生成器未直接建 `app/permissions`） | **仅在引入新权限谓词时**自建 `app/permissions/**/*.rb` 并 `eager_load_paths << root.join('app','permissions')`；否则复用宿主权限或 `enabled?` 开关（见 §5.1） |
| **decorators** | `application.rb:57`（排除 `app/decorators`） | `engine.rb` 的 `to_prepare` glob `app/decorators/**/*_decorator*.rb` | 装饰器文件命名 `*_decorator*.rb`，由引擎 `to_prepare` 手动加载 |
| **overrides（deface）** | `application.rb:58`（排除 `app/overrides`） | 仅生成 `app/overrides/.keep`，**模板未加载** | 须自行在 `to_prepare` 加 `Dir.glob(.../app/overrides/**/*.rb)`（参照 esignatures/ai_protocols） |
| **assets.precompile** | `engine.rb:7-10` initializer 预留 | 生成空 `assets.precompile` 列表 | 把需预编译资产填入该列表 |
| **static_assets** | `engine.rb:13-19` | 生成 `static_assets` initializer | 服务 `public/` 可选 |
| **migrations** | `engine.rb:35-41` `append_migrations` | 生成 `db/migrate/.keep` | 迁移置于 `db/migrate/`；宿主 `db/migrate` 零改动（append 模式） |
| **资产接线（现代）** | 宿主 webpacker | 生成 `app/assets/{javascripts,stylesheets,images}/<folders>/` | 见 §6 偏差②：模板的 Sprockets 指引已过时，实测走 webpacker entryList + `javascript_include_tag` |
| **测试/feature** | `load_addons_specs.rb:9-17,20-28` | — | 测试放 `addons/<dir>/spec`、`features`，由初始化器软链/拷贝 |

---

## 5.1 何时需要 / 不需要 `app/permissions`

> 关键澄清：§5 的「权限」行并非所有 addon 都要建 `app/permissions`。该目录**仅在 addon 引入「新的 Canaid 权限谓词」时才必须存在**；否则 addon 通过复用宿主权限或特性开关实现控制，无需该目录。

### 5.1.1 五种 addon 对照

| addon | 新权限谓词？ | 有 `app/permissions`？ | 权限实现方式 |
|---|---|---|---|
| `esignatures` | ✅ `can :sign_protocol_record` / `sign_result_record` / `sign_experiment_record`（→ `can_sign_record?`） | 有 | 引擎 `eager_load_paths << root.join('app','permissions')`（`engine.rb:14`）→ `canaid.rb` 经 `list_all_addons` 自动发现 |
| `ai_protocols` | ✅ `can :generate_protocol_with_ai` | 有 | 同上（`engine.rb:14`） |
| `i18n` | ❌ 无 | 无 | 完全无门控：`languages_controller.rb:5` `skip_before_action :authenticate_user!`（连登录都不要求，登录页可切语言） |
| `project_insights` | ❌ 无 | 无 | `enabled?` 特性开关：`lib/scinote/project_insights.rb:9` → `AddonSetting.enabled?('project_insights')`；控制器 `insights_controller.rb:35` `head :forbidden unless enabled?`；底层数据复用宿主既有权限 |
| `addon_settings` | ❌ 无 | 无 | 复用**宿主核心**权限：`can_manage_addons?`（`app/permissions/instance_admin.rb:27` `can :manage_addons`）、`can_manage_label_printers?`（宿主核心）；按 ADR-013 该跨 addon 实例级权限刻意留核心，addon 仅消费 |

### 5.1.2 三种「不需要 `app/permissions`」的情形

1. **无需门控**：功能对全员开放（如 i18n 语言切换），不定义、不消费任何 `can_*`。
2. **用 `enabled?` 特性开关替代权限**：整 addon 以 `AddonSetting.enabled?` 为总开关（project_insights），叠加在宿主对底层数据的既有授权之上，不新增谓词。
3. **复用宿主既有权限**：addon 直接调用核心已定义的 `can_*`（addon_settings 消费 `:manage_addons`）。按 ADR-013，此类跨 addon 基础设施权限留在核心，避免核心安全门控反向依赖 addon。

### 5.1.3 需要 `app/permissions` 的充要条件

当且仅当 addon 的业务逻辑需要**宿主尚未覆盖的新授权决策**时，才：
- 在 `app/permissions/scinote/<name>/permissions.rb` 用 `Canaid::Permissions.register_for(Model) do can :verb_object do |user, obj| … end end` 注册新谓词（见 esignatures / ai_protocols 实现）；
- 在引擎中 `config.eager_load_paths << root.join('app', 'permissions').to_s`，使其进入 `Rails::Engine` 实例的 `eager_load_paths`，被 `canaid.rb:14` 的 `find { |p| p.ends_with?('permissions') }` 发现并并入 `config.permissions_paths`。

---

## 6. 契约偏差与已知坑（务必知悉）

1. **README 自相矛盾（高危）**：`templates/README.md:12-16` 仍叫开发者在宿主 `config/routes.rb` 写 `mount ${NAME}::Engine => '/'`，但引擎模板 `engine.rb:47-51` 已**自挂载**。真相是宿主路由零 `mount`（`routes.rb:14-17`）。**以 engine.rb 为准，README 该段作废**。
2. **资产接线过时**：README 用 Sprockets `//= require` / `*= require`（`README.md:18-28`）。本仓现代 addon 实测走 **webpacker `config/webpack/webpack.config.js` 的 `entryList` + `javascript_include_tag`**（详见 `addon-generator.md` 引用及 ai_protocols/project_insights 实战），Sprockets 方式已非主线。
3. **版本钉死过时**：`.gemspec` 固定 `rails ~> 4.2.5`、`deface ~> 1.0`（`templates/.gemspec:23-24`），宿主实际 Rails 7.2（`application.rb:27`）、deface `~> 1.9`（`Gemfile:48`）。发布/升级时需同步。
4. **gemspec `s.files` 引用 `README.rdoc`**（`templates/.gemspec:20`，`Rakefile` rdoc 也 `include('README.rdoc')`），但生成物是 `README.md` → 打包时空引用（对 path 加载无影响）。
5. **deface 不在模板 `to_prepare` 内**：`engine.rb` 模板只 glob `app/decorators`，**不**加载 `app/overrides`。每个真实 addon 都自行补了 `overrides` glob（`app/overrides` 已被 `application.rb:58` 排除出 Zeitwerk）。新 addon 若要用 deface，**必须**自行补这一段，否则覆盖静默失效。
6. **`Rakefile` 默认 `task default: :test`** 但模板无 `test` 任务，`rake` 裸跑会失败（遗留瑕疵，不影响 path 加载运行）。
7. **`LICENSE.txt` 内容为 `TODO`**：正式使用前需补许可证文本。

---

## 7. 新增一个合规 addon 的最小清单

按契约逐项核对：

- [ ] `rails g addon Scinote::<Name>` 生成骨架（或用现有 addon 复制）。
- [ ] 目录位于 `addons/<name>/`（`name` = 最后一段 module）。
- [ ] `Gemfile` 加 `gem 'scinote_<name>', path: 'addons/<name>'`（gem 名双下划线、目录名单段，二者不同）。
- [ ] 引擎类以 `Scinote::` 开头，含 `isolate_namespace`（5 个 addon 均隔离，含 `addon_settings`；其宿主级 `addons_path` / `update_addon_path` 经 `engine.rb` `config.to_prepare` 提升）。
- [ ] 路由定义在 addon 自身 `config/routes.rb` 的 `Engine.routes.draw`；**不**动宿主 `routes.rb`。
- [ ] 用到的能力经引擎 `initializer` / `to_prepare` 自注册（i18n、权限 `app/permissions`、decorators、overrides、assets、migrations）。
- [ ] 若用 deface，在 `to_prepare` 补 `app/overrides/**/*.rb` glob。
- [ ] 现代前端资产走 webpacker `entryList` + `javascript_include_tag`，而非 README 的 Sprockets `//=` 注入。
- [ ] `db:migrate` 后验证；注释 Gemfile 行应能优雅禁用（宿主照常启动，仅该 addon 路由 404）。

---

## 8. 交叉引用

- 生成器实现与目录结构：`addon-generator.md`
- 路由自挂载与零入侵叙事、isolate_namespace 差异表：`addons-zero-intrusion.md`
- 实战接线（webpacker entryList、decorators 手动加载、view spec 坑）：addon 实战记忆（esignatures / project_insights / ai_protocols engine）
