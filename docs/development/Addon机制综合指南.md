# SciNote Addon 机制综合指南

> 本文整合自以下文档，按主题重新组织、消除重复：
> - `addon-generator.md` —— 生成器内部实现与目录产出
> - `addon-settings约定.md` —— addon_settings 模块约定与发现
> - `addons-host-contract.md` —— 宿主 ↔ addon 契约规格（总索引）
> - `addons-zero-intrusion.md` —— 以路由为重点的零入侵自注册机制
> - `SciNote-官方扩展点调研.md` —— 官方扩展点全景调研
>
> 调研来源：`scinote-web`（Rails），addon 核心是「挂载式 Rails Engine 插件」。

---

## 1. 架构总览

SciNote 的扩展体系以 **Add-on（挂载式 Rails Engine 插件）** 为核心，辅以少量内置注册表/开关机制。关键设计目标：**零入侵**——新增 addon 除在 `Gemfile` 加一行启用开关外，不改动宿主任何受管文件（`config/routes.rb`、`config/application.rb`、设置页、顶栏、controller）。

| 角色 | 义务 / 保证 |
|---|---|
| **宿主** | ① 经由 `Bundler.require` 加载 `addons/*` 下被启用的 gem；② 反射发现所有 `Scinote::*` 引擎；③ 提供通用（`addons/*` 通配）接缝：autoload 排除、i18n、权限、测试软链、迁移追加；④ 禁用 addon（注释 Gemfile 行）时**仍能正常启动**。 |
| **addon** | ① 是 `Scinote::` 前缀的 `Rails::Engine`；② 落在 `addons/<addon_name>/`；③ 在 `Gemfile` 以 `gem '<full_underscore_name>', path: 'addons/<addon_name>'` 注册；④ 能力通过引擎 `initializer`/`to_prepare` 自注册（不修改宿主 `app/`、`config/routes.rb` 等受管文件）。 |

---

## 2. 命名三轨契约（最易被坑）

生成器把 `NAME`（如 `Scinote::ProjectInsights`）拆成三套派生名，三者**用途各不相同**：

| 派生名 | 计算 | 例子 | 用在哪 |
|---|---|---|---|
| 模块名 `NAME` | 原样 | `Scinote::ProjectInsights` | 引擎类、`isolate_namespace`、权限/命名空间 |
| gem 名 `full_underscore_name` | `folders.join('_')` | `scinote_project_insights` | **Gemfile `gem` 名**、`gemspec` name、`lib/<gem>.rb` 主文件 |
| 目录名 `addon_name` | `folders[-1]` | `project_insights` | **物理目录 `addons/<addon_name>/`**、引擎 `load_localization` 路径 |

唯一的合规启用写法：

```ruby
gem 'scinote_project_insights', path: 'addons/project_insights'
#    ^gem 名(双下划线)            ^目录名(最后一段)
```

> 若写成 `gem 'project_insights'` 或 `path: 'addons/scinote_project_insights'` 都会错配——Bundler.require 的 gem 名与磁盘目录由两套不同派生名决定。模块名必须可被 `name.camelize` 还原（如 `ai_protocols` → `AiProtocols`），否则 `safe_constantize` 返回 `nil`。

---

## 3. Addon 生命周期

### 3.1 生成脚手架

`rails generate addon <NAME>`（`lib/generators/addon`，一个标准的 Rails `NamedBase` 生成器）在 `addons/<addon_name>/` 下产出完整 Engine 骨架。

- 调用：`rails g addon Scinote::ProjectInsights`（`NAME` 必须带命名空间，约定以 `Scinote::` 开头）。
- 生成顺序：`create_app` → `create_bin` → `create_config` → `create_db` → `create_lib` → `create_root`。
- `embed_into_modules` 私有方法自动把类/模块体包裹进与 `@modules` 对应的嵌套 `module` 层级，保证命名空间一致。
- 生成物含：`app/{assets,controllers,decorators,helpers,models,overrides,views}`、`config/{initializers,locales,routes.rb}`、`db/migrate`、`lib/{...,engine.rb,version.rb}`、`bin/rails`、`.gemspec`、`Gemfile`、`README.md`、`Rakefile`、`VERSION`(0.0.1)。
- 生成器不含业务逻辑，只负责搭好目录与样板文件；业务逻辑由开发者填充。

### 3.2 发现机制（反射，契约入口）

addon 不是被宿主「列举」的，而是被「反射」发现的：

1. `config/application.rb` 中 `Bundler.require(*Rails.groups)` 加载所有在 `Gemfile` 中启用的 gem。
2. 被启用的 addon gem 的 `lib/<gem>.rb`（`gemspec` 主文件）执行 `require 'scinote/<name>'; require 'scinote/<name>/engine'`（生成器垫片）。
3. `require .../engine` 触发 `Scinote::<Name>::Engine < ::Rails::Engine` 类定义。
4. 该类进入 `Rails::Engine.subclasses`，被 `list_all_addons` 反射收集：
   ```ruby
   # app/helpers/addons_helper.rb
   def list_all_addons
     Rails::Engine.subclasses
       .select { |c| c.name.start_with?('Scinote') }
       .map(&:module_parent)
   end
   ```
5. 大量宿主设施据此消费 addon：`config/initializers/canaid.rb`（权限目录扫描）、`load_addons_specs.rb`（测试/feature 软链）、路由自挂载等。

> **契约要点**：引擎类**必须**以 `Scinote` 开头（`select { ...start_with?('Scinote') }`），否则不被发现。`list_all_addons` 只识别引擎用于权限/本地化/枚举，**不会自动挂载路由**——路由可见必须靠 addon 自身的 `routes` initializer 自注册。

### 3.3 注册（唯一硬门槛）

代码能被 `safe_constantize` 够到，前提是它被 Bundler 加载——即 **Gemfile 中必须有一行**：

```ruby
gem 'scinote_<name>', path: 'addons/<name>'
```

目录存在但 addon 未注册 → 引擎不被 Bundler 加载 → 反射不到 → 不被列出（`safe_constantize` 也返回 `nil`）。移除 addon 的唯一操作就是把它从 Gemfile 注释掉（boot-safe，但会失去其能力）。

### 3.4 启用语义（opt-out）

- 未写入设置行 → 视为启用（"挂载即默认启用"）。
- `toggleable?` 返回 `false` 的 addon 永远 `true`，其开关在**任何层**都不可由用户控制（基础设施型，如 `addon_settings`、`i18n`）。
- 因此所有 addon 默认开，运维通过取消勾选来关闭。

### 3.5 优雅禁用（零入侵的关键收益）

- 禁用：注释掉对应 `gem` 行 → 引擎不被加载 → `engine.rb` 不执行 → `routes` initializer 不运行 → 宿主路由表不含该 addon 路由 → Rails 正常启动（对应页面仅 404，不崩溃）。
- 这正是「零入侵」的设计核心：**禁用绝不会破坏宿主启动**。

---

## 4. 引擎机制与自注册面

引擎模板 `lib/generators/addon/templates/engine.rb` 是扩展机制的心脏。一个 add-on 通过引擎初始化器即可注册各类能力，**无需额外胶水代码、无需改动宿主**。

### 4.1 路由自挂载（零入侵核心）

每个 addon 在自己的 `engine.rb` 中用一个 engine initializer 把路由追加进宿主 router：

```ruby
initializer 'scinote_<name>.routes', after: :add_routes do |app|
  app.routes.append do
    mount Scinote::<Name>::Engine => '/'
  end
end
```

- 主 `config/routes.rb` 中**没有任何** addon 的 `mount`/`get`/`resources` 行，仅一段解释性注释。
- 该 initializer 在 boot 期执行；`app.routes.append` 把路由追加到宿主路由表**顶层作用域**（不在 `constraints UserSubdomain` 块内，根域即可访问）。
- 使用 **append（追加，非 prepend）**：addon 路由优先级低于核心、不可覆盖核心，是有意的安全取舍。
- 路由定义在 addon 自身 `config/routes.rb` 的 `Engine.routes.draw do … end`；**不**动宿主 `routes.rb`。
- 全部 5 个 addon 均声明 `isolate_namespace Scinote::<Name>`（含 `addon_settings`）。

### 4.2 其它自注册面

| 能力 | 注册方式 | 说明 |
|---|---|---|
| **i18n** | `initializer :load_localization` 把 `addons/<name>/config/locales/*` 并入 `i18n.load_path` | **硬编码**物理锚点 `Rails.root/addons/<addon_name>/config/locales`（离开此位置静默失效） |
| **权限（canaid）** | 引擎 `config.eager_load_paths << root.join('app','permissions')` | `canaid.rb` 扫描发现路径末段为 `permissions` 的目录 |
| **decorators** | `config.to_prepare` 加载 `*_decorator*.rb` | 运行时 monkey-patch 核心模型/控制器；宿主已将其从主 autoloader 排除 |
| **overrides（deface）** | `config.to_prepare` 加载 `app/overrides/**/*.rb` | 模板**未**自带此 glob，需各 addon 自行补（见 §6 坑⑤） |
| **assets.precompile** | `initializer '…assets.precompile'` | 把需预编译资产填入列表 |
| **static_assets** | `initializer :static_assets` | 服务 `public/` 可选 |
| **migrations** | `initializer :append_migrations` | 追加 `db/migrate` 路径，宿主 `db/migrate` 零改动 |
| **Dashboard widget** | `config.to_prepare` 调 `register_widgets!` | 如 `project_insights`，晚于 `extends.rb` 确保常量已定义，带去重守卫 |

### 4.3 强制位置契约（物理锚点）

引擎模板的 `load_localization` initializer **硬编码**宿主根下的 addon 位置 `Rails.root.join('addons','<addon_name>','config','locales')`，与 `Gemfile` 的 `path: 'addons/<addon_name>'` 互为对齐。离开这个位置，i18n 文件将不会被加载且不报错的静默失效。

### 4.4 通用配置（无需逐 addon 修改）

`config/application.rb` 使用一次性通用 glob 覆盖所有 addon：

```ruby
# 自定义 DB 适配器自动加载（仅此目录）：
Dir.glob(Rails.root.glob('addons/*/lib/active_record/connection_adapters/*.rb')) { |c| ... }
Rails.autoloaders.main.ignore(Rails.root.join('addons/*/app/decorators'))
Rails.autoloaders.main.ignore(Rails.root.join('addons/*/app/overrides'))
```

新增 addon **不需要**回头修改 `application.rb`、任何 initializer 或 `routes.rb`——它们对 `addons/*` 是通用的。

---

## 5. Host Contract：addon 必满足的约定

### 5.1 目录与文件布局

```
addons/<name>/
├── lib/scinote/<name>.rb          # 定义 Scinote::<Name> 模块与约定方法
├── lib/scinote/<name>/engine.rb   # 自挂载路由（零侵入宿主）
└── ...
```

### 5.2 约定方法（供 `addon_settings` 发现 / 渲染）

`AddonSetting.addon_module(name)` 通过 `"Scinote::#{name.to_s.camelize}".safe_constantize` 解析模块；各元数据 reader 用 `respond_to?` **探测**约定方法，缺失则优雅降级。

| 方法 | 必填 | 返回 | 缺失时 | 作用 |
|---|---|---|---|---|
| `self.toggleable?` | 可选 | `true`/`false` | 默认 `true` | 是否允许实例管理员开/关 |
| `self.config_schema` | 可选 | 字段数组 | `[]`（只渲染启用开关） | 设置页据 `type` **动态**渲染配置表单 |
| `self.description` | 可选 | i18n 键 | `nil`（卡片仅显示名） | 索引卡片简介文案 |
| `self.detailed_help` | 可选 | i18n 键 | `nil`（子页不渲染说明块） | 配置子页详细说明 |

`config_schema` 字段形状（每个为 hash）：

- `key`（字符串，存储键，**必填**）
- `type`：`'boolean' | 'secret' | 'integer' | 'text' | 'select'`
- `label`：i18n 键（控件标题）；`help`：i18n 键（可选）
- `default`：缺省回退值（可选）；`placeholder`：输入提示（可选）
- `options`：`type: 'select'` 时的下拉项 `[{ value:, label: }]`（可选）

### 5.3 运行时消费契约（被管理方读取自身配置）

```ruby
def self.enabled?
  AddonSetting.enabled?('<name>')
end

def self.config_value(key)
  AddonSetting.for('<name>').config_value(key)
end
```

- `AddonSetting.enabled?` 已含 opt-out 语义与 `toggleable?` 判定，直接复用即可。
- 方向相反：第 5.2 节是 addon_settings 主动探测 addon；本节是 addon 主动读取 addon_settings。二者通过 `Scinote::<Name>` 模块这一共同锚点连接，私有套件内可直接写死 `AddonSetting` 类名。

### 5.4 何时需要 / 不需要 `app/permissions`

`app/permissions` **仅在 addon 引入「新的 Canaid 权限谓词」时才必须存在**；否则通过复用宿主权限或 `enabled?` 开关实现控制。

| addon | 新权限谓词？ | 权限实现方式 |
|---|---|---|
| `esignatures` | ✅ `can :sign_protocol_record` 等 | 引擎 `eager_load_paths << app/permissions` → `canaid.rb` 自动发现 |
| `ai_protocols` | ✅ `can :generate_protocol_with_ai` | 同上 |
| `i18n` | ❌ | 完全无门控（登录页即可切语言） |
| `project_insights` | ❌ | `enabled?` 特性开关叠加宿主既有权限 |
| `addon_settings` | ❌ | 复用宿主核心权限 `:manage_addons`（0020 跨 addon 权限留核心） |

三种「不需要 `app/permissions`」的情形：① 无需门控；② 用 `enabled?` 特性开关替代权限；③ 复用宿主既有权限。

### 5.5 路由提升（`addon_settings` 专属差异）

`addon_settings` 与其它 4 个一样声明 `isolate_namespace`，但其 `addons_path`/`update_addon_path` 被宿主代码 20+ 处直接引用。隔离后靠 `engine.rb` 的 `config.to_prepare` 把这两个 helper **提升（promote）到宿主级**（委托给引擎代理），否则隔离会把 helper 改名破坏引用。挂载点本身不受是否隔离影响，二者正交。

---

## 6. 官方扩展点全景

除 Engine 外，SciNote 还提供以下官方/半官方扩展入口：

| # | 扩展点 | 机制 | 用途 |
|---|--------|------|------|
| 1 | **Add-on（Rails Engine）** | `rails generate addon` + Gemfile + 自挂载 Engine | 最完整：模型/控制器/视图/路由/权限/本地化/迁移/资产/装饰器 |
| 2 | **类型/映射注册表 `Extends`** | 类级常量注册表，插件 initializer 直接变更 `Extends::CONSTANT` | 注册 Repository 数据类型码、搜索属性、API 映射、文件图标、Dashboard 配置、活动类型码 |
| 3 | **特性开关** | ENV→`config.x.*` + 数据库 settings 表 JSONB `values` | 启用内置但默认关闭功能（webhooks、connected_devices、API 版本） |
| 4 | **装饰器 Decorators** | `config.to_prepare` 加载 `*_decorator*.rb` | 运行时 monkey-patch 核心模型/控制器 |
| 5 | **视图覆写 deface** | `deface` gem + `app/overrides` + 核心 `data-hook` 锚点 | 在核心 ERB 视图插入/替换 UI |
| 6 | **REST API v1/v2 + Doorkeeper** | 外部 HTTP 集成 + OAuth2 | 外部系统读写 SciNote 数据 |
| 7 | **Webhooks** | 活动过滤 → 外发 POST | 事件触发外部 URL（需 `ENABLE_WEBHOOKS=true`） |
| 8 | **AssetSync 桌面端握手** | `ASSET_SYNC_URL` + Token 鉴权 API | 桌面端（SciNote Edit）拉取/回写文件 |
| 9 | **自定义 DB 适配器（addons）** | `config/application.rb` 启动时 `Dir.glob` 自动加载 | 向 addon 注入自定义 ActiveRecord 连接适配器（仅此目录自动加载） |
| 10 | **权限自动收录** | Canaid `permissions_paths` 自动追加 addon 权限目录 | 让 add-on 的权限定义参与鉴权 |

### `Extends` 注册表要点

`config/initializers/extends.rb` 中 `class Extends` 是类级常量注册表（**不存在 `def self.extends` 方法**）。插件在 initializer 中直接 `Extends::CONSTANT << value` 或 `merge!` 注入。已知常量：`REPOSITORY_DATA_TYPES`、`*_SEARCH_ATTR`、`API_VERSIONS`、`API_PLUGABLE_AUTH_METHODS`、`OMNIAUTH_PROVIDERS`、`FILE_ICON_MAPPINGS`、`DEFAULT_DASHBOARD_CONFIGURATION`、`ACTIVITY_TYPES`（注释提示 67/68/69 预留给 addons，追加码需避免冲突）。

### 编写 Add-on 完整流程

1. `rails generate addon Scinote::Addons::MyAddon` → 产出 `addons/my_addon/`。
2. 实现扩展：模型/控制器/视图放 `app/`；装饰核心类写 `app/decorators/**/*_decorator*.rb`；覆写核心视图写 deface override 到 `app/overrides/` 指向 `data-hook`；本地化放 `config/locales/`；迁移放 `db/migrate/`；权限放 `app/permissions/`；类型注册在 initializer 变更 `Extends::CONSTANT`。
3. `Gemfile` 增加 `gem 'scinote_addons_my_addon', path: 'addons/my_addon'`；路由由 addon 自身 `engine.rb` 的 `routes` initializer 自挂载（宿主 `routes.rb` 无需 `mount`）。
4. 资产接线（现代走 webpacker `entryList` + `javascript_include_tag`，非 Sprockets，见 §7 偏差②）。
5. `make docker` → `make cli` → `rake db:migrate` → `make run`。

---

## 7. 契约偏差与已知坑（务必知悉）

1. **README 自相矛盾（高危）**：`templates/README.md` 仍叫在宿主 `config/routes.rb` 写 `mount ${NAME}::Engine => '/'`，但引擎模板已**自挂载**。真相是宿主路由零 `mount`。**以 engine.rb 为准，README 该段作废**。
2. **资产接线过时**：README 用 Sprockets `//= require`/`*= require`；现代 addon 实测走 **webpacker `entryList` + `javascript_include_tag`**，Sprockets 已非主线。
3. **版本钉死过时**：`.gemspec` 固定 `rails ~> 4.2.5`、`deface ~> 1.0`，而宿主实际 Rails 7.2、deface ~> 1.9。发布/升级时需同步。
4. **gemspec `s.files` 引用 `README.rdoc`**（`Rakefile` rdoc 也引用），但生成物是 `README.md` → 打包时空引用（对 path 加载无影响）。
5. **deface 不在模板 `to_prepare` 内**：engine.rb 模板只 glob `app/decorators`，**不**加载 `app/overrides`。新 addon 若要用 deface，**必须**自行补 `app/overrides/**/*.rb` glob，否则覆盖静默失效。
6. **`Rakefile` 默认 `task default: :test`** 但模板无 `test` 任务，`rake` 裸跑会失败（遗留瑕疵，不影响 path 加载运行）。
7. **`LICENSE.txt` 内容为 `TODO`**：正式使用前需补许可证文本。

---

## 8. 新增一个合规 addon 的最小清单

- [ ] `rails g addon Scinote::<Name>` 生成骨架（或复制现有 addon）。
- [ ] 目录位于 `addons/<name>/`（`name` = 最后一段 module）。
- [ ] `Gemfile` 加 `gem 'scinote_<name>', path: 'addons/<name>'`（gem 名双下划线、目录名单段，二者不同）。
- [ ] 引擎类以 `Scinote::` 开头，含 `isolate_namespace`。
- [ ] 路由定义在 addon 自身 `config/routes.rb` 的 `Engine.routes.draw`；**不**动宿主 `routes.rb`（靠 `routes` initializer 自挂载）。
- [ ] 用到的能力经引擎 `initializer`/`to_prepare` 自注册（i18n、权限 `app/permissions`、decorators、overrides、assets、migrations）。
- [ ] 若用 deface，在 `to_prepare` 补 `app/overrides/**/*.rb` glob。
- [ ] 现代前端资产走 webpacker `entryList` + `javascript_include_tag`，而非 Sprockets。
- [ ] （可选）声明 `toggleable?` / `config_schema` / `description` / `detailed_help` 供 `addon_settings` 动态发现。
- [ ] （运行时）若需读配置，接入 `AddonSetting.enabled?` / `AddonSetting.for(...).config_value`。
- [ ] `db:migrate` 后验证；注释 Gemfile 行应能优雅禁用（宿主照常启动，仅该 addon 路由 404）。

---

## 9. 反模式 / 注意

- **不注册 Gemfile** → 目录在也不被发现（`safe_constantize` 返回 `nil`）。
- **模块命名不符合 `name.camelize`** → 元数据全部降级为空。
- **把 `toggleable? => false` 的 addon 当成可被用户关闭的插件** → 与契约矛盾（永远启用）。
- **清空/保留配置**：`AddonSetting.update_for(name, configuration: {})` 会**显式清空**（传 `{}` 即重置为 `{}`）；省略 `configuration:` 则保留已有配置。
- **试图用同名路径覆盖核心路由** → append 机制不支持（优先级低于核心），需改核心或 `prepend`。
