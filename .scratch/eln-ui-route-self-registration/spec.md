# Spec — ELN UI addon 路由自注册（补齐零入侵契约）

> Status: ready-for-agent
> 依据：`docs/development/addon-dev-workflow.md`、`addons-host-contract.md`、`addons-zero-intrusion.md`、`docs/adr/0022-addon-routes-self-registration.md`
> 审阅来源：2026-10-11 eln_ui 铁律审阅（生产容器 `rails runner` 实测佐证）
> 领域词汇：ELN UI / 引擎自注册 / 具名路由 / 零入侵 / 优雅禁用（沿用 ADR-0022 与既有 addon 文档词汇；eln_ui 无独立 `CONTEXT.md`）

## 问题陈述

ELN UI 是本仓库 5 个在役 addon 中**唯一违反零入侵铁律**的：它的 30 条路由全部寄生在宿主 `config/routes.rb` 里，自己既没有 `config/routes.rb`，`engine.rb` 里也没有路由自注册的 initializer（生产容器实测 `MOUNTED_ENGINES=[]`，5 个 addon 全部零 mount）。

后果不是"文档不合规"这么轻——契约承诺的唯一启用/禁用开关（Gemfile 一行）**失效了**：注释掉 `gem 'scinote_eln_ui'` 后，宿主路由表里那 30 条 `scinote/eln_ui/*` 仍指向一个不再被 Bundler 加载的 controller，优雅禁用（"宿主照常启动，仅该 addon 路由 404"）这条保证被打破。而本 fork 无法访问上游 GitHub，守卫"单一改动面"以换取将来 rebase 冲突最小，正是这套铁律存在的全部理由。

同时，宿主视图与 `payload` 大量依赖这些路由的**具名 helper**（payload 内 11 处全限定调用），迁移时 helper 的可见性会改变，是一个会静默 500 的高风险面。

## 解决方案

把 ELN UI 的 30 条路由从宿主 `config/routes.rb` 迁入 `addons/eln_ui/config/routes.rb`，由 `engine.rb` 的 initializer 自挂载到宿主根路径，并按 ADR-0022 与 access_control 的**已验证先例**，用一层 `define_method` 转发把具名 helper 保留在宿主 url_helpers 上，使宿主既有调用点（payload 的 11 处、宿主页面的引用）**零改动继续工作**。

迁移后：宿主 `config/routes.rb` 零 ELN UI 路由；Gemfile 一行重新成为有效开关；对外 URL 与 helper 名**逐字不变**（任何变化都视为回归）。

## 用户故事

1. 作为一个维护 SciNote fork 的开发者，我想要把 addon 的改动收敛在 `addons/eln_ui/` 内，以便将来 rebase 上游时改动面清晰、冲突最小。
2. 作为一个维护者，我想要通过注释 Gemfile 一行来禁用 ELN UI，以便在不需要该功能时干净下线，而不必担心宿主启动失败或路由指向空控制器。
3. 作为一个维护者，我想要宿主 `config/routes.rb` 里不再出现任何 `scinote/eln_ui/*` 路由，以便一眼看出哪些是上游代码、哪些是二开——这是 rebase 冲突面的唯一可靠依据。
4. 作为一个 ELN UI 使用者，我想要迁移前后所有页面 URL 完全不变，以便书签、邮件通知里已有的链接继续可用。
5. 作为 ELN UI 前端开发者，我想要 payload 下发给前端的动作 URL 不因迁移而变化，以便前端不需要同步改动任何一行代码。
6. 作为一个宿主开发者，我想要继续用现在这些名字调用 ELN UI 的具名路由 helper，以便我不必为了改路由注册位置而修改宿主视图与 service 代码。
7. 作为一个 addon 作者，我想要 ELN UI 成为第五个合规范例，以便我能照抄它的写法给下一个 addon 用，而不必重新踩前导斜杠与 helper 可见性的坑。
8. 作为一个审查者，我想要"迁移前后路由集合一致"能被机器证明，以便我不必靠人工数 30 条路由来确认没漏没多。
9. 作为一个运维，我想要能在迁移后用一条命令确认生产环境 30 条路由全部注册成功且可解析，以便在重启窗口内快速判定迁移是否健康。
10. 作为一个维护者，我想要这次迁移的决策与踩坑被写进 ADR，以便将来有人想走回头路（把路由挂回宿主）时能看到当初为什么拒绝。

## 实现决策

### 机制（沿用 ADR-0022 统一契约，不新造）

- ELN UI 新增自己的 `config/routes.rb`，在其中用引擎 route set 定义全部 30 条路由。
- `engine.rb` 增加一个路由 initializer，显式声明 `after: :add_routes`，在宿主路由之后以 `append` 方式把引擎挂载到根路径。
- 挂载点为根路径：对外 URL 必须与现状逐字一致，故引擎内路由需写完整路径（含 `/projects/...` 等既有前缀），使挂载到根后对外 URL 不变。

### 控制器命名空间（已实测的坑，不可省）

- 引擎声明了 `isolate_namespace`，其 route set 自带控制器的命名空间前缀。因此引擎内路由的控制器名**不带** `scinote/eln_ui/` 前缀，否则会解析成双层前缀导致"匹配得上但 references missing controller"。
- 引擎内路由的路径**不能带前导斜杠**，否则 Rails 7.2 的 controller 名校验会直接抛"is not a supported controller name"。
- 这两条与 access_control 的注释结论一致，属已验证先例。

### 具名 helper 的可见性（本次迁移的核心难点）

- 路由搬进引擎后，具名 helper 只存在于引擎自己的 url_helpers 上，**不会**自动出现在宿主 url_helpers。宿主页面的既有调用点会立刻 `NoMethodError`。
- 正解是在引擎的 routes initializer 内，对宿主 url_helpers 模块用 `define_method` 逐个转发这批具名 helper 到引擎 helper。
- **绝不**用 `include` 把引擎的 url_helpers 模块并入宿主：该模块自带 included 钩子会自套自，导致爆栈，且日志只有一行 `Exiting`，极难定位。此坑已在 access_control 侧踩过并留注释。
- 转发的是"方法"而非"实现"，路由形状若变化两边不必各改一遍。

### 路径遮蔽风险评估（结论：可接受，已实证）

- ADR-0022 §避撞规则要求 addon 独占唯一根前缀，并警告"同路径同动词会被宿主优先匹配导致 addon 静默 404"。
- ELN UI 的路由挂 `/projects/...`、`/experiments/...`、`/eln_res_center` 等，与宿主 `resources :projects` 的成员路由（`/projects/:id/favorite` 等）**前缀不同**，不构成遮蔽。
- 但需注意：这些路由当前在宿主文件里位于 `resources :projects` **之前**，靠位置优先；迁到 append 之后会排到其后。必须在迁移后逐条验证可达，而不是假定顺序无关。
- 迁移前后路由集合一致性由自动化断言守（见测试决策）。

### 不做的事（明确排除的替代方案）

- 不改用 `prepend` 抢优先级：会破坏 ADR-0022 的安全取舍（addon 不得覆盖核心路由）。
- 不改挂载点为 `/eln_ui` 子路径：那会让全部对外 URL 变化，与用户故事 4 冲突。ADR-0022 §升级路径把它列为"路径重叠风险升高时"的方案，当前不需要。
- 不顺带修 `enabled?` 契约缺失：那是独立议题，另开 spec。
- 不动 `access_control` 已有的 6 条宿主路由：那处是**已登记的已知债**（注释里写明"以后改走 engine mount 时可以搬"），与本次不同，且它已完成引擎侧路由文件、并只差宿主残留。

## 测试决策

好的测试只断言**外部行为**：路由集合、URL 可达性、helper 可用性，不断言文件位置或 initializer 内部写法。

### 必守的回归断言（迁移前后必须成立）

1. **路由集合一致**：迁移前登记 ELN UI 的 30 条路由的「动词 + 路径 + helper 名」三元组基线；迁移后重取并比对，三元组逐一相等（新增/缺失/改名都必须失败）。数量也必须相等（30）。
2. **可达性**：对基线中每条路由，用识别（recognition）而非仅匹配确认能解析到预期的 controller 动作——专门用来挡住"路由匹配得上但引用了不存在的 controller"这一静默 500。
3. **helper 行为**：对宿主 url_helpers 逐个断言转发后的 helper 能生成与迁移前逐字相同的路径；并断言转发是转发而非快照（改路由后 helper 行为跟着变）。
4. **契约形状**：断言宿主 `config/routes.rb` 不再含 ELN UI 路由——把铁律本身变成会失败的测试，防止将来回潮。
5. **优雅禁用**：在隔离环境里注释 Gemfile 行，断言宿主能正常启动、且 ELN UI 路径返回 404 而非异常。这是本次改动要恢复的核心保证。

### 测试先例

- 后端沿用 ELN UI 既有的 minitest + `test/run.rb` 约定（本环境 RSpec 不可用，见范围外）。
- 真机验证沿用既有接缝：容器内 `rails runner` 探针 + Playwright 端到端脚本（现成的 ELN UI 详情页/资源中心/项目列表脚本可直接复用）。**能只在容器内跑完的断言不要写成需要浏览器的测试**——路由集合与 helper 是纯 Ruby 断言，用 runner 更稳、更快。

### 覆盖范围

- 11 个 controller 动作类对应的路由全部纳入基线。
- 特别覆盖：指标 CRUD 四条、6 表网格端点（GET+POST 双动词）、项目列表 V1 孤儿路由（不在生产路径但仍须保持可达）。

## 范围外

- 不改任何 controller / service / payload 的业务逻辑——迁移只动路由注册位置与 helper 转发。
- 不补 `enabled?` 契约（ELN UI 当前无该方法，设置页开关为摆设）——独立议题。
- 不动 `access_control` 的 6 条宿主路由与 `workbench` 的 1 条——各自的债单独处理。
- 不做 RSpec 化：仓库既有 addon 测试均为 minitest，且本环境 `BUNDLE_WITHOUT` 含 test/development，RSpec 跑不起来。强行迁移会把 19 份测试变成不可运行资产。
- 不清理 `eln_ui` 迁移路径注册（`append_migrations`）——已于 2026-10-11 补齐且经生产验证。
- 不改前端 Vue 源码与 webpack entry——路由 URL 不变即无影响。

## 补充说明

### 与 ADR 的关系

本规格**执行** ADR-0022 已 Accepted 的统一契约，不新开决策；ADR 无需改写。迁移完成后应新增一条 ADR 记录"ELN UI 已完成自注册迁移"，把 `access_control` 注释里"以后改走 engine mount 时可以搬"这句待办标记为已办（ELN UI 侧）。

⚠ 仓库内存在**文档互相矛盾**，与本规格无直接关系但会误导后来人：`docs/development/addon-dev-workflow.md` 说 ADR 写入 `docs/ARCHITECTURE_DECISIONS.md`，而 `docs/agents/domain.md` 说 ADR 单一存放处是 `docs/adr/`。按后者（更新的约定）执行，建议另行修正前者。

### 已知的连带风险

- **helper 转发清单必须与基线一一对应**：漏转发一个，宿主某处渲染时才 `NoMethodError`，且只在访问该页面时暴露；多转一个无用转发。故此清单由基线测试生成，而非手写。
- **迁移涉及 30 条路由的重排**，建议一次性提交、不拆多次，以免中间态出现"部分路由在引擎、部分在宿主"的双源窗口——那正是记忆里"两套 decorator 并存"那类温床。
- 变更 `.rb` 后必须重启进程才生效（开发态 bootsnap 亦需清缓存），验收须在重启后进行。