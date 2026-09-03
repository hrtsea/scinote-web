# Addon Host Contract（插件宿主契约）

本规范定义 scinote-web 中 addon 如何被宿主**自动发现、注册与管理**。遵循此契约的新增 addon **无需修改任何业务代码（controller / 设置页 / 顶栏）**即可被 `addon_settings` 接管——唯一硬门槛是在 Gemfile 中注册一行。

约定驱动的实证来源：

- 目录发现：`Scinote::AddonSettings::AddonsController#available_addon_names`
- 模块约定发现与优雅降级：`AddonSetting.addon_module` 及 `toggleable?` / `config_schema_for` / `description_for` / `detailed_help_for`
- 自挂载与守卫式链接：`addon_settings` 的 `engine.rb`

---

## 1. 自动发现的两层机制

### 1.1 目录级发现（addon 名来源）

`available_addon_names` 扫描 `Rails.root.join('addons')` 下的**子目录**，目录名即 addon 名（按字母排序）。

- 新增一个 addon = 在 `addons/` 下新建目录 `addons/<name>/`。
- 该目录名就是它在 `addon_settings` 表中的 `name`，也是下一层约定模块的命名依据。
- **不写任何 controller**：`index` / `edit` / `update` 由 `addon_settings` 提供且完全通用，按 `available_addon_names` 动态遍历。

### 1.2 模块级约定式自描述（元数据来源）

`AddonSetting.addon_module(name)` 通过 `"Scinote::#{name.to_s.camelize}".safe_constantize` 解析出 `Scinote::<Name>` 模块；各元数据 reader 再用 `respond_to?` **探测**约定方法：

- 约定方法**缺失则优雅降级**（见第 3.2 节），绝不强依赖具体 addon。
- 管理 UI 不认识任何具体 addon，只认 `Scinote::<Name>` 模块上是否声明了某个方法——这就是"约定驱动、无需改业务代码"的根。

---

## 2. 注册（唯一硬门槛）

代码要能被 `safe_constantize` 够到，前提是它被 Bundler 加载——即 **Gemfile 中必须有一行**：

```ruby
gem 'scinote_<name>', path: 'addons/<name>'
```

（或对应的 git / 其它来源。）目录存在但 addon 未注册 → 模块不会被加载 → `safe_constantize` 返回 `nil` → 该 addon 不会被列出。

> 这也意味着移除一个 addon 的唯一操作就是把它从 Gemfile 注释掉。但要注意：`addon_settings` 自身声明 `toggleable? => false`，是**必须保持启用的基础设施**（见第 5 节），生产环境不应移除——移除虽 boot-safe，却会失去管理其它所有 addon 配置的能力。

---

## 3. Host Contract：addon 必满足的约定

### 3.1 目录与文件布局

```
addons/<name>/
├── lib/scinote/<name>.rb          # 定义 Scinote::<Name> 模块与约定方法
├── lib/scinote/<name>/engine.rb   # 自挂载路由（零侵入宿主）
└── ...
```

模块名必须可被 `name.camelize` 还原（如 `ai_protocols` → `AiProtocols`）。

### 3.2 约定方法（供 `addon_settings` 发现 / 渲染）

| 方法 | 必填 | 返回 | 缺失时 | 作用 |
| --- | --- | --- | --- | --- |
| `self.toggleable?` | 可选 | `true` / `false` | 默认 `true`（可切换） | 是否允许实例管理员开/关。返回 `false` 表示基础设施型 addon 永远启用（如 `addon_settings`、`i18n`）。 |
| `self.config_schema` | 可选 | 字段数组 | `[]`（只渲染启用开关） | 设置页据 `type` **动态**渲染配置表单。 |
| `self.description` | 可选 | i18n 键 | `nil`（卡片仅显示名） | 索引卡片简介文案。 |
| `self.detailed_help` | 可选 | i18n 键 | `nil`（子页不渲染说明块） | 配置子页详细说明。 |

### 3.3 `config_schema` 字段形状

每个字段为 hash，支持的键：

- `key`（字符串，存储键，**必填**）
- `type`：`'boolean' | 'secret' | 'integer' | 'text' | 'select'`
- `label`：i18n 键（控件标题）
- `help`：i18n 键（可选，帮助文本）
- `default`：缺省回退值（可选）
- `placeholder`：输入提示（可选）
- `options`：`type: 'select'` 时的下拉项 `[{ value:, label: }]`（可选）

示例见 `addons/ai_protocols/lib/scinote/ai_protocols.rb` 的 `config_schema`。

### 3.4 运行时消费契约（被管理方读取自身配置）

若 addon 在运行时需要读取"是否启用"或"某项配置"，接入 **AddonSetting 契约**：

```ruby
def self.enabled?
  AddonSetting.enabled?('<name>')
end

def self.config_value(key)
  AddonSetting.for('<name>').config_value(key)
end
```

- `AddonSetting.enabled?(name)` 已含 opt-out 语义与 `toggleable?` 判定，被管理方直接复用即可。
- 这与第 3.2 节"发现用约定方法"方向相反：后者是 **addon_settings 主动探测** addon；前者是 **addon 主动读取** addon_settings。两者通过 `Scinote::<Name>` 模块这一共同锚点连接，因此私有套件内可直接写死 `AddonSetting` 类名（无需中性契约隔离）。

---

## 4. 启用语义（opt-out）

- 未写入设置行 → 视为启用（"挂载即默认启用"）。
- `toggleable?` 返回 `false` 的 addon 永远 `true`，其开关在**任何层**都不可由用户控制。
- 因此所有 addon 默认开，运维通过取消勾选来关闭。

---

## 5. 路由自挂载（零侵入宿主）

每个 addon 在自己的 `engine.rb` 中 `mount Scinote::<Name>::Engine => '/'` 注册路由；**宿主 `config/routes.rb` 不写任何 addon 路由**。

- `addon_settings` 同样自挂载，并把 `addons_path` / `update_addon_path` 提升到宿主级（委托到 engine 代理），使宿主代码（sidebar、navigations_controller、label_printers_controller 等）可直接调用。
- 宿主对这些路径的引用以 **`respond_to?(:addons_path)` 守卫**，保证 `addon_settings` 不存在时链接不渲染、应用不崩（graceful disable）。

---

## 6. 新增一个 addon 的清单（checklist）

1. `Gemfile` 加一行 `gem 'scinote_<name>', path: 'addons/<name>'`。
2. 新建目录 `addons/<name>/`，并在 `lib/scinote/<name>.rb` 定义 `Scinote::<Name>` 模块。
3. （可选）声明 `toggleable?` / `config_schema` / `description` / `detailed_help`。
4. （可选）`engine.rb` 自挂载路由。
5. （运行时）若需读配置，接入 `AddonSetting.enabled?` / `AddonSetting.for(...).config_value`。
6. **不写**任何 controller、不改动设置页、不动 sidebar——管理 UI 已动态支持。

---

## 7. 反模式 / 注意

- **不注册 Gemfile** → 目录在也不被发现（`safe_constantize` 返回 `nil`）。
- **模块命名不符合 `name.camelize`**（目录名无法常量化）→ `safe_constantize` 返回 `nil`，元数据全部降级为空。
- **把 `toggleable? => false` 的 addon 当成可被用户关闭的插件** → 与契约矛盾（它永远启用）。
- **清空/保留配置**：`AddonSetting.update_for(name, configuration: {})` 会**显式清空**（传 `{}` 即重置为 `{}`）；省略 `configuration:` 参数则保留已有配置。设置页表单走 `typed_configuration` 仍是推荐的逐字段类型化写入路径。
