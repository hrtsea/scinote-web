# 0045 — 将 workbench 并入 eln_ui（消解跨 addon 硬依赖）

> 承接 ADR-0044 §遗留问题。本篇记录「workbench 硬依赖 eln_ui」这一在 ticket 03 优雅禁用
> 实验中新发现、且独立于路由迁移的耦合，如何处置，以及落地结果。

## Status

Accepted（2026-10-12）

## Context

ADR-0044 的优雅禁用实验暴露：注释 `gem 'scinote_eln_ui'` 后宿主照常启动、eln_ui 路径全部 404，
但 `/eln_workbench` 却 500（`NameError: uninitialized constant Scinote::ElnUi`）。根因是
`addons/workbench/app/services/scinote/workbench/workbench_payload.rb` 有**三处真实调用**
直引 eln_ui 的命名空间常量：

- `::Scinote::ElnUi::NotificationsPayload.unread_count_for(...)`
- `::Scinote::ElnUi::ProjectListScope.participation(...)`
- `::Scinote::ElnUi::ResourceApplication.for_team(...)`

这意味着 workbench 在役却硬依赖 eln_ui ⇒ 无法单独禁用 eln_ui 而保持 workbench 可用，
违反了「停用 addon 前必查三路引用」铁律的第一路（Ruby 命名空间常量）。

### 处置前先查清的事实（不是猜测）

为决定「解耦 vs 并入」，先核对 workbench 与 eln_ui 的真实构成：

| 维度 | 发现 |
|---|---|
| workbench 体量 | 整个 addon 仅 5 个 Ruby 文件（controller / payload / view / route / gemspec+engine）+ 1 个测试。不持有任何业务模型。 |
| workbench 前端 | 工作台 Vue 应用（Workbench.vue / entries/workbench.js）**早已在 eln_ui**：`config/webpack/webpack.config.js:145` 的入口 `eln_workbench: './addons/eln_ui/app/javascript/packs/eln_workbench.js'`。workbench 的 ERB 只是挂载 eln_ui 打出来的 `eln_workbench.{js,css}`。 |
| 路由 URL | `/eln_workbench` 被 eln_ui 与宿主**硬编码**：`eln_ui/project_list_controller.rb:431`、`eln_ui/project_list_payload.rb:185`、`elncp/controller.rb:358`、`elncp/payload.rb:184`。 |
| 数据口径 | workbench_payload 三处调用 + 注释反复声明这些 eln_ui 类是「**单一真源**」「用户拍板，勿改」；测试也直接 `assert Scinote::ElnUi::ProjectListScope`。 |
| 反向依赖 | 全仓搜 `Scinote::Workbench` 只在 workbench 自身 + 测试注释出现；**没有任何 addon / 宿主反向依赖 workbench**——它是叶子。 |
| 跨 addon 依赖声明 | 所有 addon 的 gemspec 都**不**声明相互依赖；跨 addon 依赖全是运行期裸常量引用（这正是本问题的成因）。 |

### 设计树与候选方案

```
D0 根决策：workbench ↔ eln_ui 硬耦合如何处置
├─ B  并入 eln_ui（推荐，已采纳）
│    ├─ D1 控制器命名空间改名 Scinote::ElnUi::WorkbenchController（路由才能落在 eln_ui engine 下）
│    ├─ D2 路由/path 保留 '/eln_workbench' 逐字不变（eln_ui+elncp 已写死，无选择）
│    ├─ D3 文件搬移 + 删 addon + Gemfile 去行
│    └─ D5 优雅禁用契约：禁用 eln_ui 同时禁掉 workbench（无独立场景，见下）
└─ A  解耦（保持独立 addon）
     ├─ A1 仅 gemspec 声明依赖（显式化，但不恢复独立禁用）
     ├─ A2 抽共享内核（把真源类下沉到第三方层）—— 高成本、过度设计
     └─ A3 workbench 自持副本 —— 破坏「单一真源」不变量
```

**为何淘汰 A 三条路**：
- **A3（复制真源）**：直接违反 workbench 自己的「单一真源，用户拍板勿改」，且测试断言直引
  eln_ui 类，复制会让数字口径漂开（这正是本项目两次出事的形态）。
- **A2（抽共享内核）**：要新建第三层去承载 6+ 个类，但 workbench 是叶子、无人依赖，没有
  「被多方共享」的诉求，纯属过度设计。
- **A1（gemspec 依赖）**：只把隐性依赖显式化，**并不能恢复「单独禁用 eln_ui」**——而 workbench
  的前端/URL/数据全在 eln_ui，A1 下 workbench 依然离不开 eln_ui。

**前置事实 Q2（已确认）**：不存在「workbench 单独跑 / eln_ui 禁用但 workbench 保留」的真实部署
场景——workbench 的 webpack 入口、URL 字面量、`/eln_workbench` 的 Vue 视图全部硬编码在 eln_ui，
物理上无法在不动 eln_ui 的前提下让 workbench 独立存活。即「独立禁用/workbench 独立部署」在工程上
本就不可达，不是产品需求。

## Decision

**将 workbench 整体并入 eln_ui（方案 B）。** workbench 本质是 eln_ui 的一个「仪表盘页面」，其
前端、URL、数据早已是 eln_ui 的一部分，只差把那 5 个 Ruby 文件 + 1 个测试搬过去收口。

具体落地（2026-10-12 已执行）：

1. **文件搬移（git mv 保留历史）**：
   - `addons/workbench/app/controllers/scinote/workbench/workbench_controller.rb`
     → `addons/eln_ui/app/controllers/scinote/eln_ui/workbench_controller.rb`
   - `addons/workbench/app/services/scinote/workbench/workbench_payload.rb`
     → `addons/eln_ui/app/services/scinote/eln_ui/workbench_payload.rb`
   - `addons/workbench/app/views/scinote/workbench/workbench/index.html.erb`
     → `addons/eln_ui/app/views/scinote/eln_ui/workbench/index.html.erb`
   - `addons/workbench/test/workbench_test.rb`
     → `addons/eln_ui/test/workbench_test.rb`
   - 其余（VERSION / gemspec / lib / config/routes / test/run.rb / test/test_helper.rb）`git rm` 删除，
     `addons/workbench/` 目录整体移除。
2. **模块/类名改名**：迁入文件的 `module Scinote::Workbench` → `module Scinote::ElnUi`；
   controller 内 `Scinote::Workbench::WorkbenchPayload.call` → `Scinote::ElnUi::WorkbenchPayload.call`；
   `workbench_test.rb` 约 30 处 `Scinote::Workbench::WorkbenchPayload` → `Scinote::ElnUi::WorkbenchPayload`。
3. **路由迁入 eln_ui**（`addons/eln_ui/config/routes.rb` 末尾追加，对外 URL / helper 名逐字不变）：
   `get 'eln_workbench', to: 'workbench#index', as: :eln_workbench`。
   在 `isolate_namespace Scinote::ElnUi` 下，`workbench#index` 解析为 `Scinote::ElnUi::WorkbenchController`。
4. **资产登记随迁（关键）**：workbench 原 `engine.rb` 有 `assets.precompile += [eln_workbench.js,
   eln_workbench.css]`。删 addon 时该登记会一起消失，而视图 `javascript_include_tag 'eln_workbench'`
   走 Sprockets manifest ⇒ 会整页 500（与 ADR-0022 / ADR-0038 同类坑）。已在 eln_ui 的
   `scinote_eln_ui.assets` initializer 补登 `eln_workbench.js eln_workbench.css`（与既有入口成对登记）。
5. **Gemfile / Gemfile.lock**：删 `gem 'scinote_workbench', path: 'addons/workbench'` 一行；
   Gemfile.lock 同步摘除 `remote: addons/workbench` / `scinote_workbench (0.1.0)` / `scinote_workbench!`
   三条（容器侧仍需 `bundle install --local` 权威重锁）。
6. **守卫与注释同步**：
   - `host_routes_addon_purity_test.rb`：删 `assert_includes KNOWN_ADDONS, 'workbench'`（删目录后
     KNOWN_ADDONS 已不含它）；双引号样本 `scinote/workbench/x#y` → `scinote/ai_protocols/x#y`；
     历史注释标注 workbench 已并入。
   - `eln_ui_route_baseline_test.rb`：更新 line 27-28 误导性注释——`eln_workbench` 现属 eln_ui，
     只是本 30 条基线白名单不含 `workbench`，故不计入（有意）。
   - `eln_ui_graceful_disable_test.rb`：在 2026-10-12 实测记录后追加「已解决」说明。
   - `eln_ui/app/javascript/vue/eln/data/mock.js` 两处 `addons/workbench` 注释更正为「eln_ui（已并入）」。

## Consequences

- **跨 addon 硬依赖消失**：workbench 不再作为一个独立实体需要单独照顾；它本就是 eln_ui 的功能。
- **零新增耦合、零重复**：没有抽共享层、没有复制真源；「单一真源」不变量保持。删掉一个空壳 addon，
  仓库更贴合「addon 是独立可选功能」的语义（workbench 从来不是）。
- **优雅禁用契约恢复一致**：禁用 eln_ui 现在会**连同** `/eln_workbench` 一起 404，不再出现
  「eln_ui 禁了但 workbench 500」的半残态。ADR-0044 那条遗留问题关闭。
- **资产整页 500 风险已堵**：`eln_workbench` 的 precompile 登记随路由一起迁到 eln_ui，删 addon
  不会让视图 AssetNotFound。
- **路由基线测试不受影响**：`eln_ui_route_baseline_test.rb` 用 `ENGINE_CONTROLLERS` 白名单（不含
  `workbench`）收集路由，且 `EXPECTED_COUNT=30` 比对的是基线**文件**，迁入 workbench 路由不会让它变红。
  workbench 路由的识别由生产环境 `routes_available?` 路径 + 真机 HTTP 验收覆盖。
- ⚠ **未解决、超出本决策范围**：宿主 `elncp`（controller.rb / payload.rb）同样硬依赖 eln_ui
  （直引 `Scinote::ElnUi::*`）。即「独立禁用 eln_ui」在 host 层本就不成立——这是更大的既有债，
  本篇不碰，留待后续评估是否把 elncp 也收口进 eln_ui 或抽内核。

## 关联

- 0044（addon 路由自注册全仓库收尾）—— 本篇关闭其 §遗留问题。
- 0022（addon 路由自注册统一策略）—— 并入后仍满足零入侵契约。
- `docs/CONTEXT.md`（术语表：Workbench / ELN UI / 单一真源 / 优雅禁用 / 并入 / addon 零入侵契约）。
