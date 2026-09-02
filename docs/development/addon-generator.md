# Addon Generator（`lib/generators/addon`）

## 1. 概述

`lib/generators/addon` 是一个 **Rails 应用内生成器（application generator）**，用于在 SciNote 主应用下快速脚手架（scaffold）一个新的 **addon**（插件/扩展）。

- 位置：`lib/generators/addon/`
  - `addon_generator.rb` —— 生成器主体（`AddonGenerator < Rails::Generators::NamedBase`）
  - `USAGE` —— `rails generate addon` 的帮助文本
  - `templates/` —— 复制到新 addon 的模板文件
- 命令空间（namespace）：`addon`
- 调用方式：`rails generate addon <NAME>`（或 `rails g addon <NAME>`）

`USAGE` 说明：`NAME` 必须是**完整带命名空间**的 addon 名，可包含任意层级的 module，例如：

```
Scinote::MyOrganization::MyAddon
Scinote::ProjectInsights
```

生成结果统一落到主仓库的 `addons/<addon_name>/` 目录下。

---

## 2. 命名解析（`initialize_vars`）

生成器把 `NAME` 拆解为以下实例变量，后续所有路径/类名都由此派生：

| 变量 | 计算方式 | 例（`Scinote::ProjectInsights`） |
|---|---|---|
| `@modules` | `name.split('::')` | `['Scinote', 'ProjectInsights']` |
| `@folders` | 每个 module 做 `underscore` | `['scinote', 'project_insights']` |
| `@full_underscore_name` | `folders.join('_')` | `scinote_project_insights` |
| `@folders_path` | `folders.join('/')` | `scinote/project_insights` |
| `@addon_name` | `folders[-1]`（最后一个 module） | `project_insights` |

> 注意：目录名 `addons/<addon_name>/` 取的是**最后一个** module 段（`project_insights`），而类/模块定义整体仍按 `Scinote::ProjectInsights` 嵌套。即约定 addon 名**必须以 `Scinote::` 开头**。

---

## 3. 核心辅助方法 `embed_into_modules`（private）

`embed_into_modules { ... }` 接收一个代码块（返回一段类/模块体），将其**自动包裹进与 `@modules` 对应的嵌套 `module` 层级**，并做正确的缩进。例如 `Scinote::ProjectInsights` 下：

```ruby
module Scinote
  module ProjectInsights
    class ApplicationController < ::ApplicationController
    end
  end
end
```

生成器中所有需要产出"位于某命名空间下的类/模块"的文件（controller、helper、constants、engine、version、模块入口文件）都通过它包裹，保证命名空间一致。

---

## 4. 生成步骤（按方法定义顺序执行）

Rails 生成器按 **public 方法的定义顺序**依次执行：`create_app` → `create_bin` → `create_config` → `create_db` → `create_lib` → `create_root`。

### 4.1 `create_app` —— `app/`
- `app/assets/images/<folders_path>/.keep`
- `app/assets/javascripts/<folders_path>/application.js`
- `app/assets/stylesheets/<folders_path>/application.scss`（来自模板 `application.scss`）
- `app/controllers/<folders_path>/application_controller.rb`
  ```ruby
  class ApplicationController < ::ApplicationController
  end
  ```
- `app/decorators/controllers/.keep`、`app/decorators/models/.keep`
- `app/helpers/<folders_path>/application_helper.rb`（`module ApplicationHelper`）
- `app/models/<folders_path>/.keep`
- `app/overrides/.keep`
- `app/views/layouts/<folders_path>/.keep`
- `app/views/<folders_path>/overrides/.keep`

### 4.2 `create_bin` —— `bin/`
- `bin/rails`：复制模板 `rails`，并把其中的 `${FOLDERS_PATH}` 替换为实际路径。

### 4.3 `create_config` —— `config/`
- `config/initializers/<folders_path>/constants.rb`（`class Constants`）
- `config/locales/en.yml`：内容仅 `en:`
- `config/routes.rb`：
  ```ruby
  <NAME>::Engine.routes.draw do
  end
  ```

### 4.4 `create_db` —— `db/`
- `db/migrate/.keep`

### 4.5 `create_lib` —— `lib/`
- `lib/<folders_path>/engine.rb`：复制模板 `engine.rb`，替换 `${FULL_UNDERSCORE_NAME}` / `${NAME}` / `${FOLDERS_PATH}` / `${ADDON_NAME}`（详见第 6 节）。
- `lib/<folders_path>/version.rb`：从 addon 根 `VERSION` 文件读取版本号：
  ```ruby
  VERSION =
    File.read(
      "#{File.dirname(__FILE__)}#{dots}/../VERSION"
    ).strip.freeze
  ```
  > `dots` = `@modules.map { '/..' }.join`，用于从 `lib/<folders_path>/` 回退到 addon 根读取 `VERSION`。
- `lib/<folders_path_n>/<file_name>.rb`：空的命名空间入口文件（如 `lib/scinote/project_insights.rb`，内容为嵌套的 `module Scinote; module ProjectInsights; end; end`）。
- `lib/tasks/<folders_path>/.keep`
- `lib/<full_underscore_name>.rb`：require 垫片：
  ```ruby
  require '<folders_path>'
  require '<folders_path>/engine'
  ```

### 4.6 `create_root` —— addon 根文件
- `.gitignore`（模板）
- `Gemfile`（模板）
- `LICENSE.txt`（模板，内容当前为 `TODO`）
- `README.md`（模板，替换 `${ADDON_NAME}`/`${FULL_UNDERSCORE_NAME}`/`${NAME}`/`${FOLDERS_PATH}`）
- `VERSION`：固定写入 `0.0.1`
- `Rakefile`（模板，替换 `${NAME}`）
- `<full_underscore_name>.gemspec`：复制模板 `.gemspec`，替换 `${FOLDERS_PATH}`/`${FULL_UNDERSCORE_NAME}`/`${NAME}`

---

## 5. 生成的目录结构

以 `rails g addon Scinote::ProjectInsights` 为例：

```
addons/project_insights/
├── .gitignore
├── Gemfile
├── LICENSE.txt
├── README.md
├── Rakefile
├── VERSION                      # 0.0.1
├── scinote_project_insights.gemspec
├── bin/
│   └── rails
├── app/
│   ├── assets/
│   │   ├── images/scinote/project_insights/.keep
│   │   ├── javascripts/scinote/project_insights/application.js
│   │   └── stylesheets/scinote/project_insights/application.scss
│   ├── controllers/scinote/project_insights/application_controller.rb
│   ├── decorators/
│   │   ├── controllers/.keep
│   │   └── models/.keep
│   ├── helpers/scinote/project_insights/application_helper.rb
│   ├── models/scinote/project_insights/.keep
│   ├── overrides/.keep
│   └── views/
│       ├── layouts/scinote/project_insights/.keep
│       └── scinote/project_insights/overrides/.keep
├── config/
│   ├── initializers/scinote/project_insights/constants.rb
│   ├── locales/en.yml
│   └── routes.rb
├── db/
│   └── migrate/.keep
└── lib/
    ├── scinote_project_insights.rb
    ├── tasks/scinote/project_insights/.keep
    └── scinote/
        ├── project_insights.rb
        ├── project_insights/
        │   ├── engine.rb
        │   └── version.rb
        └── (scinote/project_insights 命名空间入口)
```

> 空的目录用 `.keep` 占位（保证被 git 跟踪）。

---

## 6. Engine 行为（`templates/engine.rb`）

引擎模板注册了若干 Rails initializer，是 addon 能被主应用感知的关键：

- `engine_name 'scinote_project_insights'`：引擎名。
- `isolate_namespace <NAME>`：隔离命名空间（`Scinote::ProjectInsights`）。
- `paths['app/views'] << 'app/views/<folders_path>'`：额外挂载视图路径。
- **assets.precompile** initializer：预留 `app.config.assets.precompile` 列表（默认空，按需填加）。
- **static_assets** initializer：在 `ActionDispatch::Static` 前插入静态资源中间件，服务 `public/` 目录。
- **load_localization** initializer：把 `addons/<addon_name>/config/locales/*.{rb,yml}` 合并进 `i18n.load_path`（addon 自己的翻译文件自动生效）。
- **append_migrations** initializer：当 addon 不在主应用根时，把 `db/migrate` 路径追加进主应用迁移路径。
- **routes（自挂载）** initializer（`${FULL_UNDERSCORE_NAME}.routes`，`after: :add_routes`）：把当前引擎经 `app.routes.append { mount ${NAME}::Engine => '/' }` 挂载进宿主路由表，实现**零入侵**——宿主 `config/routes.rb` 无需写任何 `mount`。`append`（非 `prepend`）保证 addon 路由优先级低于核心、不可覆盖核心；禁用 addon（注释 Gemfile 行）时该 initializer 不执行，宿主正常启动（对应页面仅 404）。此即 `docs/development/addons-zero-intrusion.md` 描述的统一自挂载机制；与 README §8.2 的“手动在宿主 `config/routes.rb` 写 `mount`”二选一，本仓库统一采用 initializer 自挂载。
- `config.to_prepare`：**自动加载** `app/decorators/**/*_decorator*.rb`，实现装饰器（decorator）热加载。

---

## 7. 模板占位符一览

生成时会做字符串替换的 `${...}` token：

| 文件 | 占位符 |
|---|---|
| `engine.rb` | `${FULL_UNDERSCORE_NAME}`、`${NAME}`、`${FOLDERS_PATH}`、`${ADDON_NAME}` |
| `rails` | `${FOLDERS_PATH}` |
| `README.md` | `${ADDON_NAME}`、`${FULL_UNDERSCORE_NAME}`、`${NAME}`、`${FOLDERS_PATH}` |
| `Rakefile` | `${NAME}` |
| `.gemspec` | `${FOLDERS_PATH}`、`${FULL_UNDERSCORE_NAME}`、`${NAME}` |

---

## 8. 接入主应用（来自 `README.md` 模板）

1. 在主应用 `Gemfile` 中添加：
   ```ruby
   gem 'scinote_project_insights',
       path: 'addons/project_insights'
   ```
2. **（可选，默认已自动）挂载引擎**：引擎模板已通过 `routes` initializer（`after: :add_routes`）把自身挂载进宿主路由表，宿主 `config/routes.rb` 无需改动即可零入侵接入。仅当你移除了该 initializer、需要手动挂载时才在此添加：
   ```ruby
   mount Scinote::ProjectInsights::Engine => '/'
   ```
3. 若有 addon 专属 JS，在 `app/assets/javascripts/application.js.erb` 中加入：
   ```js
   //= require scinote/project_insights
   ```
4. 若有 addon 专属 CSS，在 `app/assets/stylesheets/application.scss` 顶部加入：
   ```css
   *= require scinote/project_insights/application
   ```
5. 执行：
   - `make docker`
   - `make cli` → `rake db:migrate`
   - （可选）配置 initializer / settings
   - `make run` 启动应用

---

## 9. 注意事项 / 已知小问题

调研代码发现以下几处**模板与生成物不完全一致**或需人工补完的地方，建议后续维护时注意：

1. **README 文件名不一致**：
   - `.gemspec` 的 `s.files` 包含 `'README.rdoc'`，`Rakefile` 的 rdoc 任务也 `include('README.rdoc')`；
   - 但生成器实际产出的是 `README.md`。
   - 影响：若将来 `gem build` 打包，`README` 不会被纳入；rdoc 任务找不到 `README.rdoc`（无害）。对当前"主仓库内 path 加载"用法无影响。

2. **Rails / 依赖版本写死**：`.gemspec` 固定 `rails ~> 4.2.5` 与 `deface ~> 1.0`，与主机应用的 Rails 4.2 技术栈一致。若主应用升级 Rails，需同步调整。

3. **gemspec 元信息为空**：`s.authors` / `s.email` / `s.homepage` / `s.summary` / `s.description` / `s.license` 均为空字符串；若发布到 rubygems 需补全。

4. **`Rakefile` 默认 task 为 `:test`**，但模板未定义 `test` 任务，`rake`（不带参数）会失败——属遗留脚手架瑕疵，通常不影响 addon 通过 path 加载运行。

5. **装饰器命名约定**：引擎在 `config.to_prepare` 中按 `*_decorator*.rb` 通配自动加载，新增装饰器文件请遵循该命名，否则不会被加载。

6. **`LICENSE.txt` 当前内容为 `TODO`**：正式使用前请填入许可证文本。

---

## 10. 小结

`lib/generators/addon` 是一个**标准的 Rails NamedBase 生成器**，通过命名空间拆分 + 模板复制 + 占位符替换，一键产出符合 SciNote addon 约定（以 `Scinote::` 为前缀、落到 `addons/<name>/`、自带 Engine/路由/资产/装饰器加载机制）的完整插件骨架。它不含业务逻辑，只负责"正确搭好目录与样板文件"，业务逻辑由开发者在生成后的骨架中填充。
