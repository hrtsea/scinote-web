# 0024 — F6「组长派任务给组员」的指派语义：任务指定成员（`UserMyModule`），而非实验级角色指派

> 适用范围：`addons/wechat_gateway`（命名空间 `Scinote::WechatGateway`）的 F6 指派功能。
> 依据：SciNote 宿主源码核实（本仓库 `f:\eln开发\scinote-web`，2026-09-23）。
> 关联：0023（wechat_gateway addon 总决策）。

## Status

Accepted（2026-09-23）。**实现被「待决」一节阻塞**：需先确定 addon 的指派目标（task）从何而来。

## Context

需求 F6：组长把任务指派给组员（例：组长在企业微信群 @bot 把「样品前处理」派给董岩）。

经 SciNote 宿主源码核实，以下是**事实**（非推测）：

1. **代码里不存在 `Task` 类**。任务实体是 `MyModule`（表 `my_modules`，ID 前缀 `TA`，非 STI、无子类）。`Task` 只是 UI / API / 路由层的对外名。
   - `app/models/my_module.rb:3`、`app/models/my_module.rb:6`
   - 对外 REST 用 `tasks`（`config/routes.rb:1237`），Web 页面用 `my_modules`（path `/modules`）

2. **SciNote 的「指派」有两套互不相干的机制**，都挂在任务上：

   | | `task_assignments` | `user_assignments` |
   |---|---|---|
   | 模型 / 表 | `UserMyModule` / `user_my_modules` | `UserAssignment` / `user_assignments`（多态 `assignable`） |
   | 语义 | **任务的指定成员 / 负责人**（designated users） | **角色 / 权限** |
   | 动作 | `index` / `create` / `destroy` | `index` / `show` / **`update`**（无 create/destroy） |
   | 权限门 | `can_manage_my_module?`（`MyModulePermissions::MANAGE`） | `can_manage_my_module_users?`（`USERS_MANAGE`） |
   | 活动日志 | `designate_user_to_my_module` / `undesignate_user_from_my_module` | `change_user_role_on_my_module` |

   - `app/controllers/api/v1/task_assignments_controller.rb:20-33`（create/destroy 写 `UserMyModule`）
   - `app/controllers/api/v1/task_user_assignments_controller.rb:30-43`（仅 update 角色，置 `assigned: :manually`）
   - `app/models/user_my_module.rb:4`（`validates :user, uniqueness: { scope: :my_module }`）
   - `app/models/my_module.rb:508-521`（`assign_user(user, assigned_by)` → `user_my_modules.create` + 活动）
   - `app/permissions/my_module.rb:45-47`（`manage_my_module` → `MANAGE`）、`:161-163`（`manage_my_module_designated_users` → `DESIGNATED_USERS_MANAGE`）

3. **任务卡片上显示的「负责人」来自 `user_my_modules`**，不是 `user_assignments`。

4. **`user_assignments` 无法直接 create**：`MyModule` 非顶层可指派对象，其 `user_assignments` 由 experiment 继承自动生成。
   - `app/models/concerns/assignable.rb:27`（`after_create :create_user_assignments!`）

5. **`task_users`（`GET /tasks/:id/users`）是另一个集合**：`@task.users` 不是关联而是方法，把 `user_assignments` + `user_group_assignments` + `team_assignments` 三来源并集（含继承），**不等于**指定成员。
   - `app/models/concerns/assignable.rb:29-42`
   - `config/routes.rb:1244-1246`

6. **addon 现状与其后果**：
   - `ScinoteServiceWriter#assign_user(exp_id, target_user_id, role:)` 写的是 `exp.user_assignments`，权限门 `can_manage_experiment_users?`
     - `addons/wechat_gateway/lib/scinote/wechat_gateway/scinote_service_writer.rb:81-92`
   - `Intake#assign_mentions` 传入的是**草稿实验 id**
     - `addons/wechat_gateway/lib/scinote/wechat_gateway/intake.rb:150-167`
   - **后果**：群里 @ 指派会回「已指派成功」，但写的是**实验级角色指派**（`ExperimentUserAssignment`），**任务卡片上看不到负责人**——与 F6「派活给组员」的语义不符。
   - 该现状已被 0023 第 40 行记录为「实验级；任务级待 F12」，本 ADR 正式修正该结论。

## Decision

1. **F6「派活给组员」的语义定为：把组员设为该任务的指定成员**，即写 **`UserMyModule`**（等价于 `POST /tasks/:task_id/task_assignments`）。
2. **权限门用 `can_manage_my_module?`**（`MyModulePermissions::MANAGE`），不再用 `can_manage_experiment_users?`。
3. **指派动作复用宿主模型方法 `MyModule#assign_user(user, assigned_by)`**，以自动写入 `designate_user_to_my_module` 活动，保证审计链。
4. **实验级 `user_assignments` 不再作为 F6 的落地方式**（保留给角色/权限场景，不由 F6 触发）。

## 待决（阻塞实现，需拍板）

`UserMyModule` 需要 `my_module_id`，但 addon 当前**只有实验级草稿**（`SessionDraftStore` 存 `exp_id`），**没有任何任务（`MyModule`）概念**。因此必须先定「指派目标从哪来」：

| 选项 | 做法 | 影响面 |
|---|---|---|
| **A**（推荐） | 在每个草稿实验下自动建/复用**一个主任务**（如与实验同名），指派落在该任务上 | 中：`ScinoteServiceWriter` 加建任务（`CreateMyModuleService`）+ 存 `task_id` |
| **B** | 指令显式指定任务（`指派 @董岩 任务「样品前处理」` 或 `#任务ID`），找不到则建 | 中偏大：需扩指令协议 + 任务名解析 |
| **C** | 把草稿载体从 `Experiment` 改为 `MyModule`（任务），实验仅作容器 | 大：`SessionDraftStore` / `Intake` 全链路重构 |

补充事实：**不存在 `Tasks::CreateService` / `MyModules::CreateService`**；建任务用 `CreateMyModuleService.new(user, team, params).call`（`app/services/create_my_module_service.rb:13-42`），其 `params` 用 `params[:experiment]` / `params[:project]` / `params[:my_module]`，权限门 `can_create_experiment_tasks?`，且**内部会自动把创建者 `assign_user` 为指定成员**（`:38`）。

## Consequences

- addon 需引入任务概念（至少要持久化一个 `task_id`），`Intake#assign_mentions` 与 backend（`ScinoteServiceWriter`）接口签名需改；`intake_spec` 的 `FakeBackend` 需同步。
- **重复指派陷阱**：`MyModule#assign_user` 用的是 `user_my_modules.create`（非 `create!`），而 `UserMyModule` 有 `uniqueness: { scope: :my_module }` 校验 → **重复指派会静默失败（返回未保存记录）但仍写 activity**。addon 侧必须先判重再调，避免产生假的「指派成功」回执与重复活动。
- **权限门比实验级更严**：`can_manage_my_module?` 要求 `my_module.active? && !my_module.status_changing? && experiment.active? && project.active?`（`app/permissions/my_module.rb:33-39`）。任一不满足则指派失败，需给用户可读提示。
- 群 @ 解析（`chat_id` / `mentions`）的标记格式仍待真机核实（见 0023 与 README）。
- 需同步更正 **0023 第 40 行**「实验级指派 ✅」的表述。

## 关联

- 0023（wechat_gateway addon 总决策）
- 0022（addon 路由自注册）、0005（addon 注册约定）
- `addons/wechat_gateway/README.md`（指令 / 环境变量）
- `docs/开发计划/wechat-gateway/WECHAT-SCINOTE-PLAN.md` §7（F6 任务指派流程）
