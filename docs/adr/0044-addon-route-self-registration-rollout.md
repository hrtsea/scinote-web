# 0044 — addon 路由自注册全仓库收尾

> 承接 ADR-0022（addon 路由自注册统一策略）。本篇记录该契约在**全部 addon** 上的落地结果，
> 以及落地过程中实测确认的两条实现约束。

## Status

Accepted（2026-10-12）

## Context

ADR-0022 已确立契约：**addon 路由由各自 `engine.rb` 的 initializer 自注册，宿主
`config/routes.rb` 零 addon 路由；启用/禁用只由 Gemfile 一行决定**（注释掉 ⇒ 引擎不加载
⇒ 路由不注册 ⇒ 宿主照常启动，仅该 addon 路由 404）。

但契约只写在文档里，落地情况长期没人核。2026-10-12 对全部 10 个 addon 做了一次体检，
结果是违规面比预想小，但仍有三处破坏契约的残留——它们共同点是**都不影响功能**，因此
长期无人发现：

| addon | 残留 | 是否影响功能 |
|---|---|---|
| eln_ui | 30 条路由寄生宿主 | ❌ 不影响，但**注释 Gemfile 行无法优雅禁用** |
| workbench | 1 条路由寄生宿主 | ❌ 不影响，同上 |
| access_control | 4 条死路由留在宿主 | ❌ 早已失效（helper 不可用、路由表里没有） |

## Decision

1. **全部在役 addon 已完成自注册**，宿主 `config/routes.rb` 对 addon **零残留**。
   eln_ui（30 条）与 workbench（1 条）已迁入各自的 `config/routes.rb`；
   access_control 的 4 条死路由已删除（其addon 侧 4 条本就生效，路径不同、不是双源）。
2. **新增常驻守卫** `addons/eln_ui/test/host_routes_addon_purity_test.rb`：
   断言宿主 `config/routes.rb` 不含任何 `to: 'scinote/<addon>/`，把"零残留"变成会失败的测试。
   守��对象是**文件内容**而非运行时路由表（理由见下）。

## 实测确认的两条实现约束

### 一、addon 路由迁入 engine 后，宿主侧具名 helper 必须惰性转发

`isolate_namespace` 的引擎，其具名 helper 只活在 `Engine.routes.url_helpers`，不会自动进宿主
`url_helpers`。宿主代码与 payload 用 `Rails.application.routes.url_helpers` 直接调它们时会
`NoMethodError`。

**三条朴素写法全部失败**（eln_ui 实测）：

| 写法 | 症状 |
|---|---|
| 遍历清单逐个 `define_method` 到 `url_helpers` | `instance_methods` 查得到、owner 正确、public，但 `respond_to?` **恒 false** |
| 定义到 `named_routes.@path_helpers_module` + initializer | 运行时手工调用能成，但**被后续路由初始化冲掉**；`install` 回报 `FORWARDED=29` **极具迷惑性** |
| 装 `config.to_prepare` | 生产 `cache_classes=true` 只在启动跑一次，仍早于路由就绪 ⇒ **整页 500** |

⇒ **结论：任何"启动期把方法塞进某个模块"的写法都在与 Rails 路由初始化时序赛跑，必输。**
正解是 **`method_missing` + `respond_to_missing?` 惰性转发**：只在真正被调用时才转发，
那时路由表必然已就绪，时序问题被彻底消除。`respond_to_missing?` 必须一起实现，
否则方法能调但 `respond_to?` 说没有。

**不需要转发的情况同样常见**：workbench 与 project_insights 都没有转发代码——因为宿主侧
根本没有地方调它们的 helper。**没有调用方就不需要转发**，这是干净写法而非缺失。

> 现状备注：`access_control` 的 helper 转发实测 `respond_to?` 为 true（全仓库唯一）；
> `addon_settings` 的 helper 提升实测是 `defined_not_respond`（只做到 define、没做到
> respond_to?），属既有遗留，**不在本篇范围**，留待后续处理。

### 二、测试环境与 runner 进程里 addon 的运行时路由为空

`RAILS_ENV=test` 与独立 `rails runner` 进程里，`Engine.routes` 都是 **0 条**——addon 的 routes
initializer 只在服务进程启动时执行。⇒ 依赖运行时路由表的断言在测试环境恒假。

⇒ **凡"迁移后路由是否等价"的断言，必须由真机HTTP + 静态对拍承担**，测试环境只保留
静态可判的部分（宿主文件内容、基线文件完整性）。

## 优雅禁用的实测结论（2026-10-12，容器 `scinote_web_production`）

契约的另一半——「禁用即下线、宿主照常启动」——已做**真实实验**证明（改 Gemfile + `bundle install
--local` + 重启，随后立即还原）：

| 观测 | 结果 |
|---|---|
| 注释 `gem 'scinote_eln_ui'` 后宿主启动 | **成功**（HTTP 200，零 NameError / 零启动崩溃） |
| ELN UI 全部路径（详情 / 列表 / 资源中心 / 通知 / 审批人 / 孤儿 V1 / 网格） | **全部 404**，非 500 |
| 同期 `/eln_workbench` | **500** ← 见下方「遗留问题」 |
| 还原后 Gemfile md5 与禁用前一致、全部端点 200 | **过程幂等、无残留状态** |

新增常驻守卫 `addons/eln_ui/test/eln_ui_graceful_disable_test.rb`：静态守住禁用契约的**前提**
（自有 routes 文件存在、宿主零残留、engine 有 `after: :add_routes` 的 append initializer、
Gemfile 以 `path: addons/eln_ui` 注册）。真正的禁用实验有副作用（改 Gemfile + 重启），
不适合进单测，故只在守卫注释里记录实测结果；若哪天路由被挂回宿主，守卫会先变红，
那时禁用实验也就失去意义。

## 🔴 遗留问题：workbench 硬依赖 eln_ui（跨 addon 耦合）

禁用实验中**新发现**、且**独立于路由迁移**的既有问题：
`addons/workbench/app/services/scinote/workbench/workbench_payload.rb` 有**三处真实调用**
指向 eln_ui：

- `::Scinote::ElnUi::NotificationsPayload.unread_count_for(...)`
- `::Scinote::ElnUi::ProjectListScope.participation(...)`
- `::Scinote::ElnUi::ResourceApplication.for_team(...)`

⇒ **workbench 在役却硬依赖 eln_ui**：一旦 eln_ui 被禁用，`/eln_workbench` 直接 500
（`NameError: uninitialized constant Scinote::ElnUi`）。

这不是路由迁移造成的，也不影响"eln_ui 自己能被优雅禁用"这条结论（eln_ui 的路径确实全部 404、
宿主确实正常启动）。但它意味着**当前无法单独禁用 eln_ui 而保持 workbench 可用**，而且它违反了
「停用 addon 前必查三路引用」铁律的第一路（Ruby 命名空间常量）。

**处置**：需要把三处共享逻辑下沉到二者都能引用的位置（或让 workbench 自持一份），
属独立工作，**不在本篇范围**，留作后续 spec。处置前不要单独禁用 eln_ui。

## access_control 的"待办注释"已消解

迁移前宿主 `config/routes.rb` 里有一段注释写着「路由挂在这里因为 engine 未被 mount，
以后改走 engine mount 时可以搬到 addon/config/routes.rb」——**那段注释本身是错的**：
access_control 的 engine 早已自挂载（`app.routes.append { mount ... => '/' }`），
addon 侧 4 条路由早已生效；宿主那 4 条带前导斜杠的写法在 Rails 7.2 下**根本无法被加载**
（加载即抛 ArgumentError），所以是纯死代码。

本次直接删除那 4 条，注释随之消失——比"标记为已办"更彻底。
ELN UI 与 workbench 的迁移已**完整验证**"addon 路由自注册"这条路可行，
access_control 自身无需再做迁移。

## Consequences

- 零入侵契约在仓库层面真正成立：rebase 上游时 `config/routes.rb` 是干净的，
  所有 addon 改动都收敛在 `addons/<name>/` 内——这正是该契约存在的理由（本 fork 无法访问上游）。
- 新增 addon 时若把路由写进宿主，守卫会立刻变红，不必等到审阅才发现。
- ⚠ **守卫自身的检漏教训**：初版正则只认单引号 `to: 'scinote/...'`，而自证注入用的是双引号
  ⇒ 注入违规后守卫仍全绿（**假绿**）。现已改为引号字符类 `['"]`。
- ⚠ **带前导斜杠的写法（`to: '/scinote/xxx/'`）会让 Rails 在加载 routes.rb 时就抛
  ArgumentError**（`not a supported controller name`），测试进程根本起不来 ⇒ 此时任何
  minitest 守卫都无从报红。这解释了 access_control 那 4 条为何是死代码：它们带前导斜杠，
  在 Rails 7.2 下根本无法被加载（应是旧 Rails 时代的写法）。自证样本因此只用不依赖
  Rails 成功加载的两种写法，避免把"守卫失效"与"文件本身非法"混淆。
- ⚠ 规范更正：常被引用的「路径不能带前导斜杠」**只对控制器名成立**（`translate_controller`
  的校验），**路径本身带不带斜杠都可以**（project_insights 的 `get '/insights'` 可证）。

## 关联

- 0022（addon 路由自注册统一策略）—— 本篇是其全仓库落地
- 0005（addon 注册约定）
- `.scratch/eln-ui-route-self-registration/` —— eln_ui 的 spec 与 3 张 ticket（已全部 resolved）
- `.scratch/addon-route-compliance-sweep/` —— workbench / access_control / 守卫的 spec 与 ticket
- `docs/development/addons-zero-intrusion.md`、`addons-host-contract.md`、`addon-dev-workflow.md`