# SciNote 官方扩展点调研

> 调研对象：开源 `scinote-web`（Rails 7.2 / MPL-2.0）源码。
> 源码根路径（本次调研所用副本）：`scinote-web-src/scinote-web-develop/`
> 调研方式：直接读取源码 + codebase-memory MCP 检索，**所有结论均标注源码位置**；无法在源码中直接证实的内容标记为「（待核实：仅从间接证据推断）」。
> 注：本仓库 `f:/eln/scinote-web-develop` 是另一项目（自建 ELN），**不是** SciNote 源码；以下结论全部来自 `scinote-web-src/scinote-web-develop/` 下的 SciNote 源码副本。

---

## 概述

SciNote 的官方扩展体系以 **Add-on（挂载式 Rails Engine 插件）** 为核心，配合少量内置的「注册表 / 开关」机制。官方并未提供运行时插件市场，而是通过 `rails generate addon` 脚手架 + Gemfile 引用 + `mount Engine` 的标准 Rails 引擎方式完成扩展。除此之外，可扩展面还包括：`config/initializers/extends.rb` 中的类型/映射注册表、基于 `deface` 的视图覆写（UI 注入点）、Doorkeeper OAuth2 + REST API（外部集成）、Webhooks（事件外发）、AssetSync 桌面端握手 API，以及 `Rails.configuration.x.*` / 数据库 settings 表的特性开关。

> **【仓库差异说明 / 校正】** 本报告基于 `E:` 的 SciNote 开源源码副本调研，其中记录了 addon 在自身 `engine.rb` 用 `initializer 'scinote_<name>.routes' { app.routes.append { mount Engine => '/' } }` 自注册路由、宿主 `config/routes.rb` 零修改的做法（见 `docs/addons-zero-intrusion.md` 第 2 节）。本仓库（F:\eln\scinote-web-develop）**同样适用此机制**：宿主 `config/routes.rb` 确实零 addon 路由，但 `list_all_addons` 的自动枚举**只识别引擎用于权限/本地化/枚举，并不会自动挂载路由**——路由可见必须靠 addon 自身的 `routes` initializer 自注册。此前"本项目无需 mount"的推断已被实测纠正：`ai_eln` 当前 `engine.rb` 缺该 initializer，其 `config/routes.rb` 定义的路由在宿主路由表中为 0 条（不可达）。正确约定见 `docs/adr/0005-addon-registration-convention.md`：宿主无需写 mount，但 addon 必须在自身 engine.rb 自注册路由。

---

## 总览表

| # | 扩展点 | 机制 | 用途 | 官方支持 | 源码位置 |
|---|--------|------|------|----------|----------|
| 1 | Add-on（Rails Engine 插件） | `rails generate addon` 脚手架 + Gemfile + `mount Engine` | 最完整的扩展方式：模型/控制器/视图/路由/权限/本地化/迁移/资产/装饰器 | 是（官方生成器 + 文档） | `lib/generators/addon/`；`README.md` 模板 |
| 2 | 类型/映射注册表 `Extends` | 类级常量注册表 | 注册 Repository 数据类型码、搜索属性、API 映射、文件图标、Dashboard 配置等 | 是（initializer） | `config/initializers/extends.rb` |
| 3 | 特性开关（Settings / `config.x`） | 数据库 JSONB `values` + ENV | 启用内置但默认关闭的功能（webhooks、connected_devices 等） | 是 | `config/application.rb:84-92`；`ApplicationSettings` |
| 4 | 装饰器 Decorators | Engine `config.to_prepare` 加载 `*_decorator*.rb` | 运行时扩展/monkey-patch 核心模型与控制器 | 是（引擎模板加载） | `lib/generators/addon/templates/engine.rb:53-61` |
| 5 | 视图覆写 / UI 注入（deface） | `deface` gem + `app/overrides` | 在核心 ERB 视图插入/替换 UI（含 `data-hook` 锚点） | 是（Gemfile 依赖 `deface`；视图注释确认） | `Gemfile:48`；`app/views/users/settings/account/addons/index.html.erb:107` |
| 6 | REST API v1/v2 + Doorkeeper | 外部 HTTP 集成 | 外部系统读写 SciNote 数据 | 是（官方 API + OAuth2） | `app/controllers/api/**`；`config/initializers/doorkeeper.rb` |
| 7 | Webhooks | 活动（Activity）过滤 → 外发 POST | 事件触发外部 URL | 是（需 `ENABLE_WEBHOOKS=true`） | `config/routes.rb:181`；`config/application.rb:84` |
| 8 | AssetSync 桌面端握手 | `ASSET_SYNC_URL` + Token 鉴权 API | 桌面端（SciNote Edit）拉取/回写文件 | 是（ENV 开关） | `app/controllers/asset_sync_controller.rb` |
| 9 | 自定义 DB 适配器（addons） | `config/application.rb` 启动时 `Dir.glob` 自动加载 | 向 addon 注入自定义 ActiveRecord 连接适配器 | 是（仅此目录自动加载） | `config/application.rb:52-55` |
| 10 | 权限自动收录 | Canaid `permissions_paths` 自动追加 addon 权限目录 | 让 add-on 的权限定义参与鉴权 | 是 | `config/initializers/canaid.rb:9-19` |

---

## 分节详述

### 1. Add-on：挂载式 Rails Engine（核心扩展点）

#### 1.1 脚手架生成器
`rails generate addon <Name>`（如 `Scinote::Addons::MyAddon`）在 `addons/<addon_name>/` 下产出完整 Engine 结构。

`lib/generators/addon/addon_generator.rb:1-11`（命名解析为模块路径）：
```ruby
class AddonGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('../templates', __FILE__)
  argument :name, type: :string
  def initialize_vars
    @modules = name.split('::')
    @folders = @modules.map(&:underscore)
    @full_underscore_name = @folders.join('_')
    @addon_name = @folders[-1]
  end
```
生成目录含：`app/{assets,controllers,decorators,helpers,models,overrides,views}`、`config/{initializers,locales,routes.rb}`、`db/migrate`、`lib/{...,engine.rb,version.rb}`、`bin/rails`、`.gemspec`、`Gemfile`、`README.md`、`Rakefile`（见 `addon_generator.rb:13-175`）。

#### 1.2 Engine 模板（扩展加载的核心）
`lib/generators/addon/templates/engine.rb:1-62` 是扩展机制的心脏：
```ruby
class Engine < ::Rails::Engine
  engine_name '${FULL_UNDERSCORE_NAME}'
  isolate_namespace ${NAME}
  paths['app/views'] << 'app/views/${FOLDERS_PATH}'

  initializer '${ADDON_NAME}.assets.precompile' do |app| ... end   # 资产预编译
  initializer :static_assets do |app| ... end                        # 静态资产
  initializer :load_localization do |app|                            # 本地化合并
    app.config.i18n.load_path += Dir[ Rails.root.join('addons','${ADDON_NAME}','config','locales','*.{rb,yml}') ]
  end
  initializer :append_migrations do |app| ... end                    # 迁移追加
  # 路由零入侵自注册：宿主 config/routes.rb 无需任何 mount，addon 自行挂入
  initializer '${FULL_UNDERSCORE_NAME}.routes', after: :add_routes do |app|
    app.routes.append { mount ${NAME}::Engine => '/' }
  end
  config.to_prepare do                                               # 装饰器自动加载
    Dir.glob(Engine.root.join('app','decorators','**','*_decorator*.rb')) do |c|
      Rails.configuration.cache_classes ? require(c) : load(c)
    end
  end
end
```
可见一个 add-on 通过引擎初始化器即可注册：视图路径、静态资产、本地化、迁移、装饰器。**无需额外胶水代码**。

#### 1.3 如何在主应用启用（官方 README 模板）
`lib/generators/addon/templates/README.md:5-35` 给出三步（这是官方文档化的「如何写一个 add-on」流程）：
```ruby
# Gemfile
gem '${FULL_UNDERSCORE_NAME}', path: 'addons/${ADDON_NAME}'
# config/routes.rb
mount ${NAME}::Engine => '/'
```
```js
//= require ${FOLDERS_PATH}           // app/assets/javascripts/application.js.erb
```
```css
 *= require ${FOLDERS_PATH}/application  // app/assets/stylesheets/application.scss
```
随后 `make docker` / `rake db:migrate` / `make run`。

#### 1.4 加载/发现流程（端到端）
- **不被自动发现**：主应用不会 `Dir.glob('addons/*')` 自动 `require` 插件。只有自定义的 **DB 适配器** 被自动加载（`config/application.rb:52-55`）：
  ```ruby
  Dir.glob(Rails.root.glob('addons/*/lib/active_record/connection_adapters/*.rb')) do |c|
    Rails.configuration.cache_classes ? require(c) : load(c)
  end
  ```
- 插件必须在 `Gemfile` 显式声明（`Bundler.require(*Rails.groups)`，`config/application.rb:22`），引擎经 `mount` 注册。
- 发现枚举：`app/helpers/addons_helper.rb:6-11` 通过 `Rails::Engine.subclasses` 过滤命名以 `Scinote` 开头的引擎：
  ```ruby
  def list_all_addons
    Rails::Engine.subclasses
      .select { |c| c.name.start_with?('Scinote') }
      .map(&:module_parent)
  end
  ```
- 自动加载隔离：`config/application.rb:57-58` 将 `addons/*/app/decorators` 与 `addons/*/app/overrides` 从主 autoloader 忽略，改由引擎 `to_prepare` 手动加载。
- 测试接入：`config/initializers/load_addons_specs.rb`（`AddonsSpecLoader`）把各 addon 的 `spec/`、`features/` 软链/拷贝到主工程（仅 test/development 环境，`load_addons_specs.rb:37-47`）。
- 权限自动收录：`config/initializers/canaid.rb:9-19` 遍历 `list_all_addons`，把每个引擎 `config.eager_load_paths` 中末段为 `permissions` 的目录加入 `Canaid` 的 `permissions_paths`。

**本仓库 wiki 另有官方文档**：`wiki/12-Extending-SciNote.md`（标题 "12. Extending SciNote"，介绍 add-on 扩展方式）。

---

### 2. `config/initializers/extends.rb`：类型与映射注册表

`Extends` 是一个类级常量注册表（`Extends::...`），用于向核心注入可扩展的数据类型码与映射。**这是除 Engine 外，官方支持的「注册自定义类型」入口**。

`config/initializers/extends.rb` 实际结构（`class Extends` 位于 `:6`，1-5 行为注释；**全文不存在 `def self.extends` 方法**）：

```ruby
# extends.rb（节选，非连续）
# rubocop:disable Style/MutableConstant
class Extends
  # 文件头部官方注释（:11）给出的真实扩展方式：
  # > initializer 'add_additional enum values to my model' do
  # >   Extends::MY_ARRAY_OF_ENUM_VALUES.merge!(value1, value2, ....)
  # > end
  REPOSITORY_DATA_TYPES = { ... }   # 见下文 :43-56
end
```

已证实的注册表（节选，`extends.rb`）：
- `REPOSITORY_DATA_TYPES`（行 43-56）：Repository 列数据类型码，含核心类型与扩展类型，如：
  ```ruby
  RepositoryStockValue: 12,
  RepositoryStockConsumptionValue: 13
  ```
- `AG_REPOSITORY_EXTRA_SEARCH_ATTR`（行 91-109）、`REPOSITORY_ADVANCED_SEARCH_ATTR`（行 112-140）、`REPOSITORY_ADVANCED_SEARCHABLE_COLUMNS`（行 148-162）：高级搜索字段映射。
- `API_VERSIONS = %w(v1)`（行 178）、`API_PLUGABLE_AUTH_METHODS = []`（行 181，可注入额外 API 鉴权方式）、`API_REPOSITORY_DATA_TYPE_MAPPINGS`（行 183-195）。
- `OMNIAUTH_PROVIDERS`（行 197）、`FILE_ICON_MAPPINGS` / `FILE_FA_ICON_MAPPINGS`（行 203/207，文件扩展名→图标映射，可扩展）、`RICH_TEXT_FIELD_MAPPINGS`（行 210-213）、`DEFAULT_DASHBOARD_CONFIGURATION`（行 215-219，Dashboard 组件注册）、`ACTIVITY_SUBJECT_TYPES`（行 221-224）、`ACTIVITY_TYPES`（行 266+，活动类型码表，注释「67,68,69 are in addons」表明插件可向活动类型表追加码）。
- `STI_PRELOAD_CLASSES`（行 164-172）、`INITIAL_USER_OPTIONS = {}`（行 199）。

> 使用方式：插件在自己的 `Engine#initializer` 中**直接变更 `Extends::CONSTANT`**（用 `<<` 或 `merge!`）即可注入/扩展类型。实例见 `addons/project_insights/lib/scinote/project_insights.rb:56`：`Extends::DEFAULT_DASHBOARD_CONFIGURATION << widget`（`extends.rb:11` 的官方注释也以 `merge!` 为例）。文档此前称需调用 `Extends.extends(MyRegistry)`，实测该方法不存在，此描述已订正。

---

### 3. 特性开关（配置而非代码扩展，但属官方「启用内置功能」途径）

两类激活路径：
- **环境变量 → `config.x.*`**（`config/application.rb:82-92`）：
  ```ruby
  config.x.webhooks_enabled = ENV['ENABLE_WEBHOOKS'] == 'true'
  config.x.connected_devices_enabled = ENV['CONNECTED_DEVICES_ENABLED'] == 'true'
  config.x.file_max_size_mb = (ENV['FILE_MAX_SIZE_MB'] || 50).to_i
  ```
- **数据库 settings 表 JSONB `values`**：`ApplicationSettings`（模型）持久化设置，运行时由 console 写入 `settings.values` 生效（如 `stock_management_enabled`、`forms_enabled`、`storage_locations_enabled` 等）。本仓库 AGENTS/CONTEXT 记录其为内置但默认关闭功能的开关；源码中 `config/application.rb` 仅以 ENV 形式确认了 `webhooks_enabled`、`connected_devices_enabled` 等。**其他开关（stock_management 等）的默认值来源（待核实：仅从间接证据推断，未在本次读取的 initializer 中逐一定位）。**

---

### 4. 装饰器（Decorators）：运行时扩展核心对象

引擎 `to_prepare` 加载 `app/decorators/**/*_decorator*.rb`（`engine.rb:53-61`）。这是 **monkey-patch 核心模型/控制器的官方机制**——在 `to_prepare` 阶段 `load` 文件，可直接 `class_eval`/重开核心类。主应用未使用 Draper（`Gemfile` 未见 `draper`），为纯 Ruby 重开类方式。

注意：`config/application.rb:57` 将 `addons/*/app/decorators` 从主 autoloader 忽略，确保由引擎在 `to_prepare` 显式加载（避免重复加载问题）。

---

### 5. 视图覆写 / UI 注入：`deface` + `data-hook`

- `Gemfile:48`：`gem 'deface', '~> 1.9'` —— deface 是官方依赖，**视图注入是受支持的扩展方式**。
- 注入锚点：核心视图用 `data-hook` 属性标记插入位。已证实的核心锚点示例：
  `app/views/users/settings/account/addons/index.html.erb:26-30`：
  ```erb
  <div data-hook="settings-addons-container">
    <em data-hook="settings-addons-no-addons">...</em>
  </div>
  ```
  该行 132 注释明确写道：`<%# Integrations inserted here via deface %>` —— 确认 add-on 通过 deface override 注入到该视图。
- 插件 override 文件放置于 `app/overrides/`（脚手架生成 `app/overrides/.keep`，见 `addon_generator.rb:55-56`），并由引擎 `engine_name` / `isolate_namespace` 与 deface 解析路径共同决定作用域。`app/views/<folders_path>/overrides/` 同样由 `engine.rb:4` 的 `paths['app/views'] << ...` 纳入视图解析。

> 注：brief 中假设「`AddonsController#index` 含 `data-hook`」不准确——实际控制器是 `Scinote::AddonSettings::AddonsController`（`addons/addon_settings/app/controllers/scinote/addon_settings/addons_controller.rb`，仅 `index` 列出已装 add-on/打印机的展示，不含 deface 逻辑）；deface override 由引擎在 `to_prepare` 全局注册，而非某控制器动作。

---

### 6. REST API v1/v2 + Doorkeeper（外部集成扩展点）

- API 控制器树：`app/controllers/api/` 下 v1（约 40 个控制器，如 `v1/projects_controller.rb`、`v1/inventory_items_controller.rb`、`v1/results_controller.rb`）、service 版（`service/`）、v2（`v2/results_controller.rb`、`v2/steps_controller.rb`、`v2/...`）。完整清单见 `app/controllers/api/**`。
- 开关：`config/initializers/api.rb:12-16` 用 ENV 控制版本启用：
  ```ruby
  config.x.core_api_v1_enabled = ENV['CORE_API_V1_ENABLED'] || false
  config.x.core_api_v2_enabled = ENV['CORE_API_V2_ENABLED'] || false
  config.x.core_api_key_enabled = ENV['CORE_API_KEY_ENABLED'] == 'true'
  ```
- OAuth2：`config/initializers/doorkeeper.rb` 配置 Doorkeeper；`config/routes.rb:2` `use_doorkeeper do ... end`；`config/application.rb:97-104` 在 `to_prepare` 覆写 Doorkeeper 控制器（layout、`ConnectedDeviceLogging` concern 注入）。这是官方外部鉴权/集成入口。
- 鉴权扩展点：`Extends::API_PLUGABLE_AUTH_METHODS`（空数组，可注入额外 API 鉴权方法，`extends.rb:181`）。

---

### 7. Webhooks（活动事件外发）

- 路由：`config/routes.rb:181` `resources :webhooks, only: %i(index create update destroy)`。
- 开关：`config/application.rb:84` `config.x.webhooks_enabled = ENV['ENABLE_WEBHOOKS'] == 'true'`。
- 机制：用户保存「活动过滤器」，每个过滤器绑定若干 webhook；当匹配活动发生时向目标 URL 发送指定 HTTP method 的 POST（含可选 `include_serialized_subject` 与 `Webhook-Secret-Key` 头，见 `config/locales/en.yml:5100-5125`）。属 **事件驱动的外部扩展点**（无需改核心代码即可对接外部系统）。

---

### 8. AssetSync：桌面端（SciNote Edit）握手 API

- 控制器：`app/controllers/asset_sync_controller.rb:3-9`：
  ```ruby
  skip_before_action :authenticate_user!, only: %i(update download)
  skip_before_action :verify_authenticity_token, only: %i(update download)
  prepend_before_action :authenticate_asset_sync_token!, only: %i(update download)
  before_action :check_asset_sync
  ```
- 开关：视图仅在 `ENV['ASSET_SYNC_URL'].present?` 时渲染桌面端下载区（`app/views/users/settings/account/addons/index.html.erb:11`）。
- 握手：`show` 为当前用户/资产签发 `AssetSyncToken`（`asset_sync_controller.rb:16-23`），桌面端凭 token 调 `update`/`download` 回写/拉取文件。属 **外部二进制集成点**（ENV + Token 鉴权 API）。

---

### 9. 其他官方/半官方扩展入口

- **自定义 DB 适配器自动加载**：仅 `addons/*/lib/active_record/connection_adapters/*.rb` 在启动时自动 `load`（`config/application.rb:52-55`）。
- **OmniAuth 提供方**：`Extends::OMNIAUTH_PROVIDERS`（行 197）列出可用 SSO 提供方，可扩展。
- **ActiveSupport 事件/通知**：核心活动系统（`ACTIVITY_TYPES` 码表，行 266+）更新活动时广播，Webhooks 基于其过滤。**（待核实：ActiveSupport::Notifications 订阅是否对外暴露为扩展点——本次未在源码中定位到第三方订阅约定，仅确认活动类型表可扩展。）**
- **生成器/任务/初始化器约定**：add-on 自带 `lib/tasks/`（`addon_generator.rb:141`）、`config/initializers/<folders>/constants.rb`（行 75-82）、`bin/rails`（行 67-71），均为 Rails 标准约定，可在插件内自由定义。

---

## 编写 Add-on 的完整流程（从 `rails generate addon` 到启用）

> 以下为 README 模板 + 生成器源码综合得出的官方流程。

1. **生成脚手架**
   ```bash
   rails generate addon Scinote::Addons::MyAddon
   ```
   产出 `addons/my_addon/`（见 `addon_generator.rb:13-175`），含 Engine、路由、权限目录、装饰器、overrides、locale、迁移、gemspec、README。

2. **实现扩展**
   - 模型/控制器/视图：放进对应 `app/` 子目录（命名空间 `Scinote::Addons::MyAddon`）。
   - 装饰核心类：写 `app/decorators/**/*_decorator*.rb`（引擎 `to_prepare` 自动加载，`engine.rb:53-61`）。
   - 覆写核心视图：写 deface override 到 `app/overrides/` 或 `app/views/<folders_path>/overrides/`，指向核心 `data-hook`（如 `settings-addons-container`）。
   - 本地化：放 `config/locales/`（引擎 `:load_localization` 自动合并，`engine.rb:22-32`）。
   - 迁移：放 `db/migrate/`（引擎 `:append_migrations` 自动追加，`engine.rb:35-41`）。
   - 权限：放 `app/permissions/`（Canaid 自动收录，`canaid.rb:9-19`）。
   - 类型注册（如新 Repository 类型）：在插件 initializer 中直接变更 `Extends::CONSTANT`（如 `Extends::REPOSITORY_DATA_TYPES.merge!(...)`），无需调用 `Extends.extends`（`extends.rb` 无此方法）。

3. **在主应用登记**
   - `Gemfile` 增加 `gem 'scinote_addons_my_addon', path: 'addons/my_addon'`（`README.md:5-10`）。
   - `config/routes.rb` 增加 `mount Scinote::Addons::MyAddon::Engine => '/'`（`README.md:12-16`）。

4. **资产接线（如需）**
   - JS：`app/assets/javascripts/application.js.erb` 加 `//= require <folders_path>`。
   - CSS：`app/assets/stylesheets/application.scss` 加 `*= require <folders_path>/application`（`README.md:18-28`）。

5. **安装与启用**
   - `make docker` → `make cli` → `rake db:migrate`（运行插件迁移）。
   - `make run` 启动；（可选）在设置页 `Scinote::AddonSettings::AddonsController#index` 查看插件状态。

---

## 边界与限制

**可安全进行的（受官方机制支持）：**
- 通过 Engine 新增模型、控制器、路由、视图、API 端点、迁移、资产、本地化（`engine.rb` 全套初始化器）。
- 通过 **装饰器** monkey-patch/扩展核心模型与控制器（`config.to_prepare` 加载）。
- 通过 **deface** + `data-hook` 注入/替换核心视图 UI（`Gemfile` 依赖 deface，视图注释确认）。
- 通过 **Canaid** 自动收录插件权限（`canaid.rb`）。
- 通过 **`Extends`** 注册新 Repository 数据类型码、搜索属性、API 映射、文件图标、Dashboard 组件、活动类型码。
- 通过 **ENV 开关** 启用内置功能（webhooks、connected_devices、API 版本）。
- 通过 **REST API + Doorkeeper** 做进程外集成；通过 **Webhooks** 接收活动事件；通过 **AssetSync** 对接桌面端。
- 自定义 ActiveRecord 连接适配器（仅 `addons/*/lib/active_record/connection_adapters/*.rb` 自动加载）。

**需要 Fork 核心 / 不受支持的：**
- 主应用**不会自动发现** `addons/*` 下的插件——必须手动在 `Gemfile` 引用（否则引擎不加载，`list_all_addons` 也枚举不到）。注意：`list_all_addons` 自动枚举**只识别引擎用于权限/本地化/枚举，不会自动挂载路由**；路由要可见，addon 必须在自身 `engine.rb` 用 `initializer 'scinote_<name>.routes' { app.routes.append { mount Engine => '/' } }` 自注册（宿主 `config/routes.rb` 仍零修改）。详见 `docs/addons-zero-intrusion.md` 第 2 节与 ADR-0005。
- 插件命名必须以 `Scinote` 开头才被 `list_all_addons` 识别（`addons_helper.rb:9`），否则权限/本地化/测试接入不会自动收录。
- 修改核心**非 deface 覆盖点**的视图逻辑、改动核心 schema 迁移、替换核心服务实现，均需改核心代码（fork）。
- 核心活动类型码采用固定整型枚举（`ACTIVITY_TYPES`，`extends.rb:266+`），插件追加码需避免与核心冲突（核心注释提示 67/68/69 预留给 addons）。
- 数据库 settings 表开关若仅由 ENV 控制（如 `webhooks_enabled`），则不能通过 console 设置 `values` 覆盖（见 `config/application.rb:84` 直接读 ENV）。

---

## 相关链接 / 参考源码文件清单

- 生成器与模板：
  - `lib/generators/addon/addon_generator.rb`
  - `lib/generators/addon/templates/engine.rb`
  - `lib/generators/addon/templates/README.md`
  - `lib/generators/addon/templates/{application.scss, Gemfile, .gemspec, Rakefile, rails, LICENSE.txt}`（同目录）
- 发现/加载/权限：
  - `app/helpers/addons_helper.rb`（`list_all_addons`）
  - `config/initializers/load_addons_specs.rb`（`AddonsSpecLoader`）
  - `config/initializers/canaid.rb`（权限自动收录）
  - `config/application.rb:52-58`（DB 适配器自动加载 + decorators/overrides 忽略）
- 注册表：
  - `config/initializers/extends.rb`（`Extends` 类与全部注册表）
- UI 注入：
  - `Gemfile:48`（`deface` 依赖）
  - `app/views/users/settings/account/addons/index.html.erb`（含 `data-hook` 锚点：`settings-addons-container` @ 行 27、`settings-addons-no-addons` @ 行 51；行 132 注释 `<%# Integrations inserted here via deface %>`）
  - `addons/addon_settings/app/controllers/users/settings/account/addons_controller.rb`
- 外部集成：
  - `app/controllers/api/**`（v1/v2/service 控制器树）
  - `config/initializers/api.rb`（API 版本/鉴权开关）
  - `config/initializers/doorkeeper.rb`、`config/routes.rb:2`（`use_doorkeeper`）
  - `config/routes.rb:181`（webhooks 路由）、`config/application.rb:84`（webhooks 开关）
  - `app/controllers/asset_sync_controller.rb`（桌面端握手）
- 文档：
  - 本仓库 wiki：`wiki/12-Extending-SciNote.md`（"Extending SciNote" 官方扩展指南）
  - 生成器自带：`lib/generators/addon/templates/README.md`

---

> **调研声明**：以上所有结论均基于 `scinote-web-src/scinote-web-develop/` 下的 SciNote 源码直接读取与 MCP 检索；凡标注「（待核实：仅从间接证据推断）」之处，为本次未在源码中逐一定位到直接证据的推断，建议后续以 `grep`/读源码二次确认。本次调研为只读，未修改任何应用代码。
