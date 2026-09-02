# Addons 零入侵机制调研（以路由注册为重点）

> 调研对象：`scinote-web/addons/*` 与宿主 `config/routes.rb`、`config/application.rb`、
> `config/initializers/*`、`Gemfile`。
> 核心问题：**addon 是否实现对宿主的零入侵，尤其是路由如何注入。**

---

## 1. 结论速览

| 宿主文件 | 是否零入侵 | 说明 |
|---|---|---|
| `config/routes.rb` | ✅ 完全零入侵 | 不含任何 addon 路由，仅一段解释性注释 |
| `config/application.rb` | ✅ 零入侵 | 仅一次性通用 glob（`addons/*/...`），无逐 addon 修改 |
| `config/initializers/addon_loader.rb` | ✅ 零入侵 | 整文件已注释（遗留 React 加载器，停用） |
| `config/initializers/load_addons_specs.rb` | ✅ 零入侵 | 仅 test/dev 软链 addon spec，非运行时侵入 |
| `Gemfile` | ⚠️ 唯一触碰点 | 每个 addon 需一行 `gem ... path: 'addons/x'` 作为启用开关 |

**路由零入侵成立**：addon 通过各自引擎的 initializer 在 boot 时把路由追加进宿主 router，
主 `config/routes.rb` 不被修改；禁用 addon（注释 Gemfile 行）不会破坏宿主启动。

---

## 2. 路由如何“增加”——自注册机制

每个 addon 在自己的 `engine.rb` 中用一个 **Rails engine initializer** 把路由追加进宿主 router：

```ruby
# addons/<name>/lib/scinote/<name>/engine.rb
initializer 'scinote_<name>.routes', after: :add_routes do |app|
  app.routes.append do
    mount Scinote::<Name>::Engine => <mount_point>
  end
end
```

- 该 initializer 在 Rails 启动期执行，`app` 为 `Rails::Application`。
- `app.routes.append { ... }` 把路由追加到 `Rails.application.routes`（宿主路由表）的**顶层作用域**。
- 主 `config/routes.rb` 中**没有任何** addon 的 `mount` / `get` / `resources` 行。

主路由文件中的相关注释（`config/routes.rb` 第 14–17 行）：

```ruby
# Addons self-register their routes via each engine's `initializer`
# (see addons/<name>/lib/scinote/<name>/engine.rb). No `mount` line lives
# here on purpose: a disabled addon (commented out in the Gemfile) simply
# does not load, so its route registration never runs and Rails boots fine.
```

> **与生成器模板的关系（`addon-generator.md`）**：生成器产出的 `engine.rb` 模板（§6）现已包含 `routes` initializer（`${FULL_UNDERSCORE_NAME}.routes`，`after: :add_routes`），把引擎自挂载进宿主路由表，宿主 `config/routes.rb` 无需手动 `mount`；README §8.2 的手动挂载因此改为可选。本仓库 5 个 addon 均沿用同一机制；差异仅在 `isolate_namespace`：`i18n`/`ai_protocols`/`esignatures`/`project_insights` 遵循模板默认（隔离命名空间），`addon_settings` 是有意例外（不隔离，以保留宿主命名空间的控制器与 `addons_path` / `update_addon_path` helper）。

### 统一机制：挂载引擎（5 个 addon 一致）

所有 addon 现在都走**同一套**自挂载机制——各自 `engine.rb` 的 initializer（带 `after: :add_routes`）里 `app.routes.append { mount <Engine> => <mount_point> }`，并在 addon 自己的 `config/routes.rb` 中通过 `Engine.routes.draw do … end`（即生成器 §4.3 的 `<NAME>::Engine.routes.draw do … end` 模板形式）定义路由。`addon_settings` 已从早先"直射宿主路由（裸 `get/put`、无 `config/routes.rb`）"改造为正规挂载引擎（见 ADR-016），故不再存在"两种注册方式"之分。

差异仅在于**是否声明 `isolate_namespace`**（决定路由 helper 名与控制器解析上下文），而非注册机制本身：

| 子类 | 采用 addon | 做法 |
|---|---|---|
| **挂载引擎 + `isolate_namespace`** | `i18n`、`ai_protocols`、`esignatures`、`project_insights` | 引擎声明 `isolate_namespace Scinote::<Name>`；`config/routes.rb` 用 `Engine.routes.draw do … end` 定义隔离命名空间下路由（如 `get '/insights'`），挂载点 `'/'`。 |
| **挂载引擎 + 无 `isolate_namespace`** | `addon_settings` | 不声明 `isolate_namespace`；其控制器本就在宿主命名空间（`Users::Settings::Account::AddonsController`），且 `addons_path` / `update_addon_path` 被宿主代码 20+ 处直接引用；保留宿主命名空间可零破坏迁移，路由挂在宿主既有前缀 `/users/settings/account/addons`。若加 `isolate_namespace` 会把 helper 改名为 `scinote_addon_settings_addons_path` 并破坏全部引用。 |

> 注意：`app.routes.append` 使用的是 **append**（追加到末尾），而非 `prepend`。

---

## 3. 优雅禁用（零入侵的关键收益）

启用/禁用 addon 的唯一开关在 `Gemfile`（第 143–147 行）：

```ruby
gem 'scinote_i18n', path: 'addons/i18n'
gem 'scinote_ai_protocols', path: 'addons/ai_protocols'
gem 'scinote_esignatures', path: 'addons/esignatures'
gem 'scinote_project_insights', path: 'addons/project_insights'
gem 'scinote_addon_settings', path: 'addons/addon_settings'
```

- **禁用**：注释掉对应 `gem` 行 → 引擎不被 Bundler 加载 → `engine.rb` 不执行 → `routes` initializer 不运行 → 宿主路由表不含该 addon 路由 → Rails 正常启动（对应页面仅 404，不崩溃）。
- 这正是“零入侵”的设计核心：**禁用绝不会破坏宿主启动**。

---

## 4. 关键边界与坑

1. **路由优先级（append 而非 prepend）**
   addon 路由追加在宿主路由表**末尾**，匹配顺序靠后。addon **无法用同名路径覆盖核心路由**——这是有意的安全取舍，保证 addon 不会误伤核心行为。若需覆盖核心路由，当前机制不支持（需改用 `prepend` 或调整核心路由）。

2. **顶层作用域**
   `app.routes.append` 加在宿主 router 的**顶层**，**不在** `constraints UserSubdomain` 块（宿主 `config/routes.rb` 第 19 行起）内。因此 addon 路由在根域即可访问，不受用户子域约束影响。

3. **`isolate_namespace`**
   生成器模板（`addon-generator.md` §6）默认给每个 addon 引擎声明 `isolate_namespace <NAME>`（路由/控制器/视图在隔离命名空间下，避免与宿主及其它 addon 命名冲突）。现有 addon 中 4 个遵循该默认：`i18n`、`ai_protocols`、`esignatures`、`project_insights`。例外是 `addon_settings`：它**不**声明 `isolate_namespace`，因为其控制器本就在宿主命名空间（`Users::Settings::Account::AddonsController`）、且 `addons_path` / `update_addon_path` 被宿主代码大量直接引用；保留宿主命名空间才能零破坏迁移（否则 helper 改名为 `scinote_addon_settings_addons_path` 并破坏全部引用）。挂载点本身不受是否隔离影响，二者正交。

---

## 5. 其它自注册面（同样零入侵）

除路由外，addon 的能力也通过引擎自注册，无宿主代码改动：

- **本地化**：引擎 `initializer` 把 `addons/<name>/config/locales/*` 并入 `i18n.load_path`（如 `i18n`、`addon_settings` engine）。
- **权限（canaid）**：`esignatures`/`ai_protocols` engine 通过 `config.eager_load_paths << root.join('app', 'permissions')` 显式注册权限目录，由 `config/initializers/canaid.rb` 扫描发现。
- **装饰器 / 视图覆盖（deface）**：各 engine 在 `config.to_prepare` 中手动 `Dir.glob(...app/decorators/**/*_decorator*.rb)` / `app/overrides/**/*.rb` 加载。原因：宿主 `config/application.rb` 已用 `Rails.autoloaders.main.ignore('addons/*/app/decorators')` 与 `…app/overrides` 将其从主 autoloader 排除，故需引擎在 `to_prepare` 手动加载（见 `project_insights`、`esignatures`、`ai_protocols` engine 注释）。
- **Dashboard widget**：`project_insights` engine 在 `config.to_prepare` 中调用 `Scinote::ProjectInsights.register_widgets!` 注册洞察 widget（晚于 `config/initializers/extends.rb`，确保 `Extends::DEFAULT_DASHBOARD_CONFIGURATION` 已定义；带去重守卫防止开发环境重载时重复注册）。
- **资产预编译**：`i18n` engine 通过 `initializer '…assets.precompile'` 把 `scinote/i18n/application.js` 加入预编译列表。
- **静态资源 / 迁移**：生成器模板 `engine.rb` 预留 `static_assets`、`append_migrations` initializer（追加 `db/migrate` 路径）。

---

## 6. 通用配置（无需逐 addon 修改）

`config/application.rb`（第 50–58 行）使用一次性通用 glob 覆盖所有 addon：

```ruby
# Load custom database adapters from addons
Dir.glob(Rails.root.glob('addons/*/lib/active_record/connection_adapters/*.rb')) do |c|
  # ...
end
Rails.autoloaders.main.ignore(Rails.root.join('addons/*/app/decorators'))
Rails.autoloaders.main.ignore(Rails.root.join('addons/*/app/overrides'))
```

新增一个 addon **不需要**回头修改 `application.rb`、任何 initializer 或 `routes.rb`——它们对 `addons/*` 是通用的。

---

## 7. 总评

- **路由零入侵 ✅**：宿主 `config/routes.rb` 零修改；addon 通过 `engine.rb` 的 `initializer + app.routes.append` 自注册。
- **广义零入侵 ✅**：宿主受管文件中，除 `Gemfile` 的逐 addon 启用行外，其余均为一次性通用配置或已停用/测试期文件。
- **安全取舍**：append（非 prepend）保证 addon 路由优先级低于核心、不可覆盖核心；禁用即彻底下线、不影响启动。
- **唯一启用开关**：`Gemfile` 中的 `gem 'scinote_x', path: 'addons/x'`。
