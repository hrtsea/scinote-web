# Addon 二次开发 · AI 辅助最佳实践流程

> 适用范围：本仓库（scinote-web）的 fork 进行二次开发，统一以 `addons/<name>/` 形式的 Rails Engine 实现。
> 配套技能：`codebase-memory`（结构查询 / 影响面分析）、`mattpocock-skills`（grill / TDD / 代码评审）。
> 仓库约定见 `AGENTS.md` 与 `docs/agents/domain.md`：ADR 统一写入 `docs/ARCHITECTURE_DECISIONS.md` 的「三、关键架构决策（ADR）」章节（编号 ADR-00N），使用 `CONTEXT.md` 术语表词汇，冲突现有 ADR 时显式标注而非静默覆盖。

---

## 〇、铁律（最重要）

所有改动**只**收敛进 `addons/<你的addon>/` 一个 Rails Engine，**绝不直接编辑核心 `app/` 代码**。

理由：本 fork 为本地、且当前环境无法访问 GitHub（无法 pull 上游）。守住「单一改动面」，将来 rebase 上游时改动面清晰、冲突最小。任何「直接改核心更快」的冲动都应改为「用引擎扩展点」。

---

## 一、Addon 契约（AI 必须遵循的硬规则，已核实源码）

addon 是**标准 Rails Engine**，不是插件目录。

1. **引擎骨架**：`addons/<name>/lib/scinote/<name>/engine.rb` 定义
   `Scinote::<Name>::Engine < ::Rails::Engine`，带 `isolate_namespace Scinote::<Name>`，
   并配 `addons/<name>/scinote_<name>.gemspec`（参考 `addons/i18n`）。
2. **Gemfile 注册**：`gem 'scinote_<name>', path: 'addons/<name>'`（每个 addon 一行）。
3. **路由挂载（自注册，不污染主 `routes.rb`）**：addon 在自己的
   `engine.rb` 中通过 `initializer` 自行 `append` 挂载，**主程序
   `config/routes.rb` 不出现任何 addon 的 `mount` 行**。
   ```12:20:scinote-web/addons/i18n/lib/scinote/i18n/engine.rb
     # Self-register routes on the host app root...
     initializer 'scinote_i18n.routes' do |app|
       app.routes.append do
         mount Scinote::I18n::Engine => '/'
       end
     end
   ```
   好处：addon 是「可插拔」的——注释掉 `Gemfile` 中对应 `gem` 行后，
   引擎不加载、该 `initializer` 不运行、路由不注册，Rails 启动**不会**因
   缺少常量而崩溃。旧范式在主 `routes.rb` 硬编码 `mount` 会在卸载 addon 时
   抛 `uninitialized constant ... NameError` 导致启动崩溃。这是铁律
   「单一改动面」的强化：**卸载 addon 时主程序零改动**（只撤 `Gemfile` 一行）。
4. **扩展点（替代改核心）**：
   - **枚举 / 常量**：用 `Extends` 类（`config/initializers/extends.rb`）在引擎
     `initializer 'add ...' do Extends::XXX.merge!(...) end` 中合并扩展，
     **不要改 `extends.rb` 本体**。`extends.rb` 注释已警告「!!!Check all addons for the correct order!!!」——多 addon 时枚举值顺序有依赖。
   - **权限**：把文件直接丢进 `addons/<name>/app/permissions/**/*.rb`，
     `config/initializers/canaid.rb` 会自动扫描所有名为 `Scinote` 开头的引擎并加入
     `permissions_paths`，**无需手动登记**。
     ```7:19:scinote-web/config/initializers/canaid.rb
         # Include the included addons' permissions folders
         rx = %r{^.*(addons/.*/app/permissions)$}
         list_all_addons.each do |addon|
     ```
   - **改核心行为**：用 `app/decorators/`（引擎 `to_prepare` 块加载，参考
     `addons/i18n/lib/scinote/i18n/engine.rb`）或 `app/overrides/`（deface 式）。
     `config/application.rb` 已把它们从 autoload 排除、由引擎手动加载。
     ```57:58:scinote-web/config/application.rb
         Rails.autoloaders.main.ignore(Rails.root.join('addons/*/app/decorators'))
         Rails.autoloaders.main.ignore(Rails.root.join('addons/*/app/overrides'))
     ```
   - **自定义 DB 适配器**：`addons/*/lib/active_record/connection_adapters/*.rb`
     会被 `config/application.rb` 自动加载。
5. **测试**：addon 的 `spec/` 由 `config/initializers/load_addons_specs.rb` 符号链接到
   `spec/addons/<name>/`、`features/` 复制到 `features/addons/<name>/`——**rspec / cucumber 自动识别**，
   因此 addon **必须自带测试**。
   ```9:17:scinote-web/config/initializers/load_addons_specs.rb
     def mount
       FileUtils.rm_f Dir.glob("#{Dir.pwd}/spec/addons/*")
       available_addons.each do |addon|
         specs_path = "addons/#{addon}/spec"
   ```
6. **自动发现**：`app/helpers/addons_helper.rb` 用
   `Rails::Engine.subclasses.select { |c| c.name.start_with?('Scinote') }` 发现 addon，
   故引擎类名**必须以 `Scinote` 开头**。

---

## 二、AI 辅助开发流程（分阶段执行）

### Phase 0 — 建项目记忆
- 让 AI 先读 `AGENTS.md`、`docs/agents/domain.md`。
- 把「本 addon 的扩展契约 / 命名空间 / 覆盖的核心点」作为**第一条 ADR**（ADR-00N）写入
  `docs/ARCHITECTURE_DECISIONS.md` 的「三、关键架构决策（ADR）」章节，遵循本仓库 ADR 约定。

### Phase 1 — 探索 hook 点（技能：`codebase-memory`）
- 用知识图谱定位「在哪里挂」：谁调用目标方法、有哪些扩展点（`Extends` 里哪个键、
  `ACTIVITY_TYPES` 为 addon 预留的区段 67–69 / 97 / 149–157 等）。
- 计算影响面（fan-in / fan-out），避免改到被多处复用的叶子模块。
- 优先用 LSP / `search_graph`，不要靠全文 grep 猜。

### Phase 2 — 设计先 grilling（技能：`mattpocock-skills` 的 `/grill` `/grill-with-docs`）
- **先逼出假设再写代码**：addon 暴露哪些路由 / 权限 / 枚举值？与上游未来版本是否冲突？
- grilling 通过后才进入 Phase 3。设计结论补进 ADR。
- 若结论与某现有 ADR 矛盾，显式标注「Contradicts ADR-00X — 重开原因…」，不静默覆盖。

### Phase 3 — 脚手架
- 按「一、Addon 契约」搭引擎：`gemspec` + `engine.rb` + Gemfile 一行 + routes 一行 `mount`。
- AI 可复制 `addons/i18n` 骨架，但必须带正确的 `isolate_namespace`。

### Phase 4 — TDD 红绿切片（技能：`mattpocock-skills` 的 TDD 工作流）
- 先在 `addons/<name>/spec/` 写失败 spec（权限、枚举扩展、装饰器行为）。
- 最小实现让它变绿。
- addon 自带测试会自动进 `spec/addons/`，跑 `rspec` 验证。

### Phase 5 — 验证
- `rubocop`（仓库已配 `rubocop-rails` / `rubocop-performance`）守风格；
- `brakeman` 守安全；
- `rspec` 跑 addon 测试；
- 检查 `Extends` 合并顺序（多 addon 场景）。

### Phase 6 — 收口
- ADR 补「与上游的冲突风险点」（扩展了哪个 `Extends` 键、覆盖了哪个核心方法），
  方便后续 rebase 时快速定位。
- 清理临时探索产物，确保改动面仅限 `addons/<name>/`。

---

## 三、最小命令清单（PowerShell）

```powershell
# 跑指定 addon 测试
bundle exec rspec spec/addons/<你的addon>

# 风格 + 安全
bundle exec rubocop addons/<你的addon>
bundle exec brakeman
```

---

## 四、检查清单（每次开发前自检）

- [ ] 改动是否**全部**在 `addons/<name>/` 内？有无直接编辑核心 `app/`？
- [ ] 引擎类名以 `Scinote` 开头？`isolate_namespace` 正确？
- [ ] Gemfile 已注册（路由由 addon 引擎自注册，主 `config/routes.rb` 不含 addon 的 `mount`）？
- [ ] 枚举扩展走 `Extends` 合并，而非改 `extends.rb`？
- [ ] 权限文件落在 `app/permissions/**/*.rb`，未被手动登记？
- [ ] addon 自带 `spec/`（如有 UI 行为再加 `features/`）？
- [ ] 是否新增 / 更新了对应 ADR？
- [ ] 设置页逻辑是否位于 `addons/addon_settings`（控制器 / view / helper / locale / 路由均不落在核心 `app/`）？
- [ ] `rubocop` + `brakeman` + `rspec` 全绿？
