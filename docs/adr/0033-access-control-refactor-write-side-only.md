# 0033 — access_control addon 重构目标形态：读写分离，判定权归还宿主

## Status

Proposed

## Context

### 触发原因

用户明确判定：`access_control` addon 的现有实现**不是最佳实践，需要重构**。据此，本 ADR **不把 addon 现有实现作为约束条件**——不寻求与它的向后兼容，也不以它的结构为起点推导目标形态。

因此本 ADR 有一个特殊的方法论声明：

> **本文所有事实依据均来自宿主 scinote-web 原生源码核查（含行号），不引用 addon 代码。**
> 下文出现的「addon 现状症状」仅来自项目既往记录中的形态描述，**重构实施时必须逐条复核后再引用**——它们的作用是确认问题类别，不是设计输入。

### 宿主能力核查结论（本次调研增量）

以下 5 点是决定重构形态的关键，均为一手核查所得：

| # | 发现 | 证据 | 意义 |
|---|---|---|---|
| E1 | **addon 可原生贡献 Canaid 权限位**，无需改宿主任何文件 | `config/initializers/canaid.rb`：`config.permissions_paths << 'app/permissions/**/*.rb'`，随后遍历 `list_all_addons`，把每个 addon 的 `addons/*/app/permissions` 路径追加进去 | 官方扩展点，**零 monkey-patch** |
| E2 | **自定义角色是一等公民** | `app/models/user_role.rb:8-16`：`predefined: false` 的角色要求 `created_by` / `last_modified_by` 必填，`permissions` 需 `presence: true, length: { minimum: 1 }`；关联 `has_many :user_assignments / :user_group_assignments / :team_assignments` | 权限组合无需平行表表达 |
| E3 | **物化链路有官方开关与回调契约** | `app/models/concerns/assignable.rb:9` `attr_accessor :skip_user_assignments`；`:27` `after_create :create_user_assignments!, unless: -> { skip_user_assignments }`；`:76` `def has_permission_children?`；`:145` `def create_user_assignments!(user = created_by)` | 想调整物化时机，**有受支持的入口** |
| E4 | 8 个模型接入 `Assignable` | `project / experiment / my_module / protocol / repository / report / form / team` | 覆盖面已足够，无需自造资产类型 |
| E5 | 继承父指针在 7 个模型上有定义 | `permission_parent`：`project.rb:120`、`experiment.rb:268`、`my_module.rb:531`、`protocol.rb:367`、`repository.rb:93`、`report.rb:99`、`form.rb:41` | 沿树写入是可行的 |

### 需要被消灭的问题类别（**已由 INV-001 阶段 1 盘点校正**）

> ⚠️ 本节初稿依据的是既往记录的 4 类症状。经 `reviews/INV-001-access_control能力盘点.md` 逐资产核查，**其中两条不成立、范围需收窄**。以下为校正后版本，取代初稿。

**成立（真问题）**

1. **劫持宿主流转**——9 个 decorator 均以 `prepend` 注入宿主类。其中真正高危的只有 1 处：`visibility_strategy_decorator` 覆写 `UserAssignments::InheritUserAssignmentsJob` 的**私有方法** `assign_to_experiment`。该方法是内部实现细节、无契约保证，宿主一旦改动即脆断。**（可行替换方案已验证，见 INV-001 第五节：官方开关 `skip_user_assignments`。）**
2. **审计缺失**——只记录 grant，不记录 revoke 的反向事件，权限变更无法完整回溯。

**不成立（盘点证伪，勿据此施工）**

3. ~~平行真相~~ —— `access_control_manual_grants` 的全部读取点仅 3 处（2 处矩阵 UI 读数、1 处 revoke 自保），**无一处参与回答「这个人能不能看这条记录」**；全仓排除本 addon 后对这两张表的引用为 **0**。真实可见性 100% 由宿主 UA 行承担。该表的正确身份是 **provenance（出处）表**，宿主无对应物，属真缺口（见 INV-001 GAP-1），**不是该删的平行产物**。
4. ~~污染宿主模型（加列）~~ —— 该问题**已被 addon 自我修正**：`20261002150000` 曾给原生 `projects` 表加 `experiment_visibility_strategy` 列，`20261005210000`（OPEN-11）已将其迁入自有表 `access_control_project_strategies`，孤儿列按项目铁律故意保留但不再读写。
   （同源但**较轻**的一条仍成立：`Project` 上仍被 prepend 了 `ac_visibility_strategy` 等属性方法，属「注入方式」问题，属 **MOVE** 而非重写。）

### 由此修正的核心判断

> **初稿说「形态错了，需全量重写」——不准确。**
> 盘点确认：9 个 decorator **全部落在写路径**，无任何一个在 HTTP 读请求上做权限判定。
> 也就是说本 ADR 定的目标（addon 只在写侧存在）**已基本达成**。
> 真问题从「形态错了」收敛为「**机制脆弱**」：不是重写，是**去 prepend 化 + 替换 Job 劫持**。

上述 1、2 两类真正成立的问题是 ADR-0010 精神（集中式、依托原生机制）的反面，须消除；3、4 两类按 INV-001 的 GAP 单独决议，不得夹带删除。

### 一个必须先说的前提约束

`SCOPE-001` 与 `GBAC-001` 共同指出：**宿主核心判定面零测试覆盖**——`readable_by_user` / `with_granted_permissions` 在 `spec/` 中命中数为 **0**；现有涉及 `user_group` 的 11 个 spec 全是 request spec，测的是「能不能把组挂上去」，不是「挂上去之后能不能看」。

这意味着重构是在**没有读侧安全网**的情况下动权限。因此安全网必须先于重构完成（见「迁移路径 · 阶段 0」）。

## Decision

### 核心原则：读写分离

> **addon 只在「写侧」存在，负责决定挂哪一行指派；读侧判定 100% 交还宿主引擎，运行时不残留任何 addon 代码路径。**

由此推出一句话判定标准，用于裁决任何重构争议：

> **任何在 HTTP 请求路径上被调用、且是用来回答「这个人能不能看这条记录」的 addon 代码，都是必须在本次重构中删除的代码。**

### 目标形态：策略写入器（Strategy Writer）

策略不再是运行时的拦截器，而是一个**纯函数**：

```
输入：对象 + 触发事件 + 策略配置
处理：计算应该存在的指派集合（期望态）
输出：对 UA / UGA / TA 的 apply / revoke 操作（全部落在宿主原生表）
```

关键性质：**变更一旦落库，addon 就此退场**。后续该对象的可见性完全由宿主自己算——**这一点在宿主升级之后依然成立**。这是消灭第 1 类症状（劫持流转）的根本手段：没有运行时钩子，就不需要 patch。

### 能力映射表：addon 想做的事，宿主用什么实现

重构时不许自造轮子，一律按下表落地：

| addon 需求 | 宿主原生机制 | 依据 |
|---|---|---|
| 定义精细角色 | 自定义 `UserRole`（`permissions` 数组自由组合） | E2 |
| 指定某人可见 | `UserAssignment` | `assignable.rb:145` |
| 某个组可见 | `UserGroupAssignment` + `UserGroupMembership` | `GBAC-001`（生产 157 条在用） |
| 全队可见 | `TeamAssignment` | `permission_extends.rb` `TOP_LEVEL_ASSIGNABLES` |
| 临时提升 / 降级 | 改 UA 行的 `user_role_id` | E2 关联 |
| 下级自动继承 | `InheritUserAssignmentsJob` + `permission_parent` / `has_permission_children?` | E3 / E5 |
| 禁止自动物化 | `skip_user_assignments` | E3 |
| 「前置条件满足才可」 | Canaid **同名权限多次注册 = AND** | `app/permissions/project.rb:7-27` |
| 「自己的东西自己能改」 | `*_MANAGE_OWN` 权限位，不写 `== user` | `permission_extends.rb` |
| addon 专属权限谓词 | addon 自己的 `app/permissions/**/*.rb` | E1 / ADR-0010 |
| 功能开关 | `ApplicationSettings.instance.values` | 参照 `UserGroup.enabled?` |

### 明确禁止清单

| 禁止 | 原因 |
|---|---|
| `prepend` / `alias_method` 改写宿主 Job 或 Model 方法 | 宿主升级即脆断；且已被 Looking E1/E3 证明无必要 |
| 建立**读时被查询**的权限产物表 | 与三源并存 = 平行真相 |
| 往宿主 Model 挂 addon 属性 | 污染宿主，合并冲突源 |
| controller / service 里手写三源 join | 唯一出口必须是 `with_granted_permissions` |
| addon 自行判定 `readable_by_user` | 判定权唯一归属宿主 |
| 裸 `Model.all` 进 controller | 现状 fail-open，忘写 scope 即全量泄漏 |

> 允许保留：**纯写侧的策略定义 / 配置表**。判定标准同样是上面那句——它是否在读路径上被 JOIN？是则删，否则留。

### 三条不可动摇的硬约束

1. **`team_id` 永不丢失**——三源每条分支都要过滤，这是多租户硬边界。
2. **尊重「个人指派排他」**——某人有 direct UA 时，UGA / TA 完全出局（`permission_checkable_model.rb` 中 `where.not(id: with_user_assignments)`）。**这是特性不是 bug**：精确锁定单人请用它；反过来，想让组生效必须先清掉那人的 personal UA。
3. **fail-closed**——宿主现状整体是 fail-open（忘写 scope = 静默返回全量，已真实发生过）。全仓唯一正例是 `app/models/storage_location.rb:30` 的 `next StorageLocation.none`，把它升格为项目规约。

## 备选方案与权衡

| 方案 | 描述 | 收益 | 代价 / 风险 | 裁决 |
|---|---|---|---|---|
| **A. 全量重写为策略写入器** | 按本 Decision 执行，删除一切运行时拦截 | 一劳永逸消灭 4 类症状；宿主升级免疫；与 ADR-0010 一致 | 一次性投入大；需迁移既有数据；需先建安全网 | **推荐** |
| B. 就地加固 | 保留运行时拦截，仅补测试 + 护栏 + 去 hardcode | 投入小、见效快 | 症状只是被测试钉住，**形态仍是错的**；下次宿主升级照样脆断 | 不推荐（治标） |
| C. 完全删除 addon | 只留原生 UI + 操作规约文档 | 零维护成本 | 生产 157 条 UGA + 141 条 `self_only_researcher` 角色正在用，说明业务需求真实存在；纯靠文档拦不住操作类错误 | 不可行 |

**选择 A 的核心理由**：B 的成本会被重复支付——每次宿主升级都要重写 patch；而 C 会丢掉已经被生产验证为刚需的能力。A 的一次性成本换来的是**宿主升级免疫**，这是唯一符合「架构能被下一个团队维护」标准的选项。

## 迁移路径

### 阶段 0 — 安全网（**硬前提，不可跳过**）

宿主核心判定面目前零覆盖。在没有护栏的情况下重构权限 = 盲改。

- 已存在：`addons/access_control/test/scope001_host_data_scope_guard_test.rb`（10 用例 / 69 runs 全绿，已通过变异自证：注入变异后**恰好 1 条**精确变红）。其**物理位置在 addon，但断言对象全部是宿主机制**，addon 重构不波及它——**它是本次重构的安全网，不得删除**。
- 待补：`RBAC-001` / `GBAC-001` 指出的 UGA 判定面覆盖（此前因「addon 待重构」被搁置，此处解除——但应补到**宿主侧 spec**，而非 addon 侧 minitest）。
- 退出条件：宿主三源的每一条分支都有对应的对照用例（普通成员 / 队 owner / 跨组成员 / 组内成员）。

### 阶段 1 — 冻结与盘点 ✅ **已完成**

产出：`reviews/INV-001-access_control能力盘点.md`。结论要点：

- 9 个 decorator **全部在写路径**，无读路径参与 ⇒ 目标形态已基本达成，**不是全量重写，是去 prepend 化**。
- 真·高危只有 1 处：`InheritUserAssignmentsJob` 私有方法劫持（替换方案已验证可行：`skip_user_assignments`）。
- 3 个真缺口须单独决议（provenance / 默认隔离策略 / 矩阵 UI 存废），**不得夹带删除**。
- 其中 **GAP-2 / GAP-3 属产品判断**，建议先裁决再动代码——可能把重构范围砍掉一半。

### 阶段 2 — 双写 + 对拍

新旧并存一段时间：**新逻辑写宿主指派，旧逻辑保留**；对同一批对象做 seen 集合对拍。差异必须能逐条解释清楚，不是「差不多就行」。

### 阶段 3 — 切读（切换点）

把读路径上的 addon 代码全部摘除。这一步完成后，addon 在请求路径上**零调用**。

### 阶段 4 — 清退平行表 + 补审计

- 删除读时被查询的产物表（数据已在三源中）。
- 审计改为 **append-only**：grant 与 revoke 都必须留痕（宿主原生亦缺此能力，属净增量）。

### 前置阻塞项 ✅ **OPEN-L 已裁决（2026-10-07）**

`OPEN-L`（单位管理员列表底座口径）**已裁决，采用宿主原生口径**，阶段 2 不再有口径分歧：

- **管理员（有 `team_manage`，当前生产仅 Team#1 Owner = hpxing 一人）绕过 `readable_by_user`，看到本工作区全队所有项目，且包含模板项目。**
- **列表底座包含模板项目**（不再排除 `projects.template`）；eln_ui 现状的"排模板"是偏离，应回退对齐宿主。
- 目标行集合基准 = 宿主原生语义：管理员走「全队分支」、普通成员走 `readable_by_user` 的「scope 分支」，**两条分支都含模板**。
- 裁决理由：管理员看不到 = 管不了（前次清理 286 个归档项目须直连 DB，正是因为 eln_ui 列表只显示 3）；含模板是宿主原生行为，不是 bug。
- 现在阶段 2 对拍可用「宿主原生口径」作为唯一基准，两套行集合口径对齐，不再有 unexplained diff——呼应项目铁律「同一事实只许一个真源」。

## 回滚

- 阶段 0–1：纯增量，可逆。
- 阶段 2（双写）：按 feature flag 回滚，回退后旧逻辑接管；风险期，需留足观察窗口。
- 阶段 3（切读）：**不可一键回滚**。因此阶段 2 的对拍必须先达到「差异可完全解释」，并以 drifting 0 差异持续运行一段时间作为准入条件。
- 阶段 4：删表前须完成数据迁移校验（三源行数可对拍）。

## Consequences

### 变得更容易

- **宿主升级免疫**：无 monkey-patch、无宿主模型污染。
- **真相唯一**：权限判定只有一个引擎（`permission_checkable_model` + Canaid），只查三张表。 `SCOPE-001` 里「同一事实两套算法」这类症状（如 `ProjectListRows` 的 286 vs 3）失去生存土壤。
- **审计可用**：append-only 后权限变更可回溯。
- **性能**：判定退化为宿主原生 SQL，不再叠加 addon 层的多次查询。

### 变得更难 / 代价

- **写路径的思考成本上升**：从「运行时判断一下」变成「必须算出并落库期望态」，对账模型更复杂。
- **异步物化的时间窗**：`create_user_assignments!` 后由 `InheritUserAssignmentsJob` 异步铺开，**写路径不能假设已完成**，否则读到旧集合。这是必须写进代码的事实，不是可以忽略的细节。
- **策略表达力受限于三源**：任何想在三源之外表达的权限语义，都必须走 E1 的 Canaid 自定义权限位，而不是新建表。这是有意为之的收敛。
- **一次性迁移成本**：157 条 UGA + 141 条自定义角色指派需安置。

## 验收标准

每一条不变式都必须有对应护栏，且**必须通过变异测试自证**（注入违规 → 精确变红；恒绿护栏比没有更危险）：

1. 组成员能看到 UI 放行的对象；成员移出后**立即**看不到。
2. 某人有 direct UA 时，组与团队的放行被屏蔽。
3. 无 direct UA 时，组 ∪ 团队取并集。
4. 跨 team 成员一律不可见（三源每条分支的 `team_id` 过滤）。
5. 宿主判定面在 `spec/` 中不再是 0 命中。

## 关联

- **0010**（集中式权限模型，Accepted）——本 ADR 是其**延伸**：0010 确立了「addon 权限谓词走 `app/permissions` 自动发现」，0033 确立「addon 连谓词都不该在判定路径上持有，只在写侧决定指派」。二者不冲突。
- **0005**（addon 注册约定）、**0022**（路由自注册）——同族：addon 一律靠宿主自发现机制接入。
- 调研依据：`reviews/RBAC-001-宿主Canaid权限模型.md`、`reviews/SCOPE-001-数据权限层现状调研.md`、`reviews/GBAC-001-用户组RBAC原生机制.md`。
- 关联决策依赖：`OPEN-L`（**已裁决**：管理员绕过 scope 看全队且含模板，阶段 2 对拍基准已定）。
