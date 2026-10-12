# 0046 — addon_settings helper 转发修复（具体 define_method，非 method_missing）

- 状态：已落地（2026-10-12）
- 上游：ADR-0022（addon 路由自注册）、ADR-0044（全仓库路由自注册）、ADR-0045（workbench 并入 eln_ui）

## 背景 / 问题

`addon_settings` 是 `isolate_namespace` 引擎，其具名路由 helper（`addons_path` /
`edit_addon_path` / `update_addon_path`）只活在 `Engine.routes.url_helpers` 上。宿主多处
代码直调并**用 `respond_to?(:addons_path)` 守卫兜底**：

- `app/controllers/navigations_controller.rb:73`
- `app/views/users/settings/_sidebar.html.erb:16,19`
- `app/controllers/label_printers_controller.rb:64,145`
- `features/step_definitions/navigation_steps.rb:29`

旧写法（`config.to_prepare` 内 `module_eval define_method` 到 `url_helpers`）实测失效：
宿主守卫 `respond_to?(:addons_path)` 恒 false ⇒ "Addons" 设置入口静默消失、
label_printers 重定向永远回退到自身。

## 决策

把转发**具体 `define_method`** 到宿主 `@path_helpers_module`（稳定的运行期真身），
路径与 URL（`_path` / `_url`）都定义。

### 关键事实（容器实测，非推测）

1. `Rails.application.routes.url_helpers` **每次访问返回新实例**——装上去即丢；
   稳定的真身是 `named_routes.instance_variable_get(:@path_helpers_module)`（`ph`），
   运行期 controller/view 的 helper 链经 `url_helpers` 的祖先 include 它。
2. Rails 的 route helper 模块**重写了 `respond_to?` 且不 consult `respond_to_missing?`**。
   因此 `method_missing` + `respond_to_missing?`（eln_ui 范本的写法）装上去后，
   `respond_to?` 仍 false、调用抛 `NoMethodError`。只有把方法**真正 define 出来**，
   `respond_to?` 才会返回 true。
3. `eln_ui` 的 method_missing 范本之所以"真OK"，是因为它的宿主调用方**不依赖
   `respond_to?` 守卫**（直接调），method_missing 转发 CALL 即可；addon_settings 依赖
   守卫，故不适用。

### 实施要点（`addons/addon_settings/lib/scinote/addon_settings/engine.rb`）

- `ADDON_SETTINGS_ROUTE_HELPERS = %i[addons edit_addon update_addon]` 为清单（与
  `config/routes.rb` 的 `as:` 名一一对应，不手抄）。
- `install_route_helpers!(app)`：`ph` + `url_helpers` 两个模块都装（顺带，ph 为生效方），
  对每个 base 具体 `define_method("#{base}_path" / "#{base}_url")`，引擎 helper **懒取**
  （避免捕获被重建前的路由表）。
- `config.to_prepare` 调用（路由已绘制后，ph 稳定）。
- 优雅禁用契约保持：注释 Gemfile 行 ⇒ engine.rb 不加载 ⇒ 转发不安装 ⇒
  `respond_to?(:addons_path)` 自然 false ⇒ 守卫自动 fallback。

### 守卫

`addons/addon_settings/test/addon_settings_helper_forwarding_test.rb`：
- 静态漂移检查：清单 ↔ `routes.rb` 的 `as:` 名一致（防漏/错一个只在访问某页才炸）。
- 运行期断言（路由已绘制的服务进程里跑，如生产容器）：宿主消费对象
  `respond_to?(:addons_path)` 为 true 且 `addons_path` 返回正确路径。
- `run.rb` 走 `rails runner`（与 eln_ui 同约定）。

## 后果

- ✅ 用户设置里的 "Addons" 入口恢复可见（守卫不再恒 false）。
- ✅ label_printers 重定向在 addon 启用时正确回到 addons。
- ✅ 优雅禁用契约不破坏（禁用时守卫自动 fallback）。
- ⚠ 复用教训：**凡宿主用 `respond_to?(:x_path)` 守卫兜底、且 x 来自 isolate_namespace
  引擎的 helper，必须具体 define_method 到 `@path_helpers_module`，method_missing 范本无效。**

## 遗留

- 核实更正：本节原称「宿主 `elncp` 硬依赖 `Scinote::ElnUi::*`、独立禁用 eln_ui 在 host 层不成立」——
  **此结论不成立**。详见 ADR-0045 §核实：`elncp/` 是被 `.gitignore` 排除、运行期零引用的迁移前快照副本，
  非在役控制面板，不构成宿主耦合；宿主运行期对 eln_ui 的真耦合面仅 `_db/seed_*.rb` 数据脚本（非 boot 路径）。
  ⇒ **无 elncp 遗留债需另行评估**，本节"待处理项"取消。
