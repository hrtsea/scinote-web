# ADR-0041: 行级「访问权限」弹窗复用原生 AccessModal 契约（修角色下拉空 + 新增成员 404）

## Status
**Accepted**

> 已实现并通过**生产真浏览器端到端验证**（2026-10-09，commit `751de74e3`）：
> 真点「添加成员」→ `POST /access_permissions/projects?id=34` → **200**，成员 1→2；
> 再点移除复原 2→1，无数据残留；`pageErrors=(无)`。

## Context

用户在 `/eln_project_list` 行菜单点「访问权限」，弹窗里：

- **成员行的「角色」下拉是空的窄白框**（截图直击）——即原生应该有 8 个角色（Owner / User / Technician / Viewer / Demo…）却一个 option 都没有；
- **「添加成员」的用户下拉恒空**，无法新增成员。

### 根因：不是后端缺端点，而是自写解析错配了原生契约

宿主原生 `shared/access_modal/` 早已有完整实现，`access_permissions` 路由的成员 CRUD 与
`user_roles` / `users_filter` 端点都在服役。ELN 弹窗是自己重写的一份，**把原生契约读错了**：

| # | 错配点 | 原生真相 | 症状 |
|---|---|---|---|
| 1 | `user_roles` 当 `[{id,name}]` 对象解析 | `UserRolesHelper#user_roles_collection` 生成 `[display_name, id]`，`AccessPermissions::BaseController#user_roles` 又 `.map(&:reverse)` 一次 ⇒ 流到前端是**二维元组** `[[id, display_name], ...]`；原生 `edit.vue` 就是按 `role[0]`/`role[1]` 取下标 | `option.value`/`text` 皆`undefined` ⇒ 空窄白框 |
| 2 | 弹窗只拉 members + user_roles，没接候选池 | 「添加成员」候选池真源 = `projects#users_filter`，返回 `{ data: [[id, name, {avatar_url}], ...] }`；它在**页面级** payload 里，而行作用域只有 `params` | 候选下拉恒空 |
| 3 | 新增成员 POST 到 member 路径 | `POST /access_permissions/projects(.:format)`（collection `#create`，靠 `?id=` 查询串反查 `@model`）才存在；`/access_permissions/projects/:id` 只有 GET/PATCH/PUT/DELETE，**没有 POST** | 新增必 404 |

第3 条是**自查路由表抓出来的**，用户当时还没点到那一步——即「静态全绿但写路径坏死」。

### 次生问题：两份 `RowActionModal` 并存

| 文件 | 状态 |
|---|---|
| `addons/eln_ui/app/javascript/vue/eln_project_list/renderers/row_action_modal.vue` | 实际被 pack 加载，**有上述 bug** |
| `addons/eln_ui/app/javascript/vue/eln/components/overlays/RowActionModal.vue` | 原型树 `vue/eln/` 下，**未注册进 webpack entryList**，已正确实现并注释记录了坑 |

同类实现两份、且正确的那份根本没上线，是这类 bug 的温床。

## Decision

### 1. 按原生契约解析（三处修法都写进 payload 注释，防回归）

- `loadAccess()` 改按二维元组解析 `user_roles`，并**同时防御** `[id,name]` 与 `[name,id]` 两向
  （`Number(first)` 判定哪端是 id），不依赖 `.reverse` 次数这种实现细节。
- 成员列表按 AMS 的 **JSON:API 形状**取：`attributes.user` / `attributes.user_role`
  （AMS 默认 adapter 渲染集合时会把 user 埋在 attributes 里，不能按顶层 `.user` 读）。
- 「已指派」排除放在**前端 diff**（拿本弹窗成员列表比对候选池），语义等价于原生在服务端算。

### 2. 端点随行下发（不是随页下发）

行作用域拿不到页面级 UI payload，所以「打开弹窗时才知道要拉什么」的那些端点必须挂在行动作上。
与 `move` 带 `folders_tree_url` 同款：

```ruby
access: action(:access, 'GET', access_permissions_project_path_of(project), project,
               assignable_users_url: assignable_users_path_of,
               create_access_url: access_permissions_projects_path_of(project)),
```

新增helper `access_permissions_projects_path_of`，注释写明「为什么不是 member 路径」，防止后人再写错。

### 3. 未来方向：整车复用原生 `AccessModal`（本次**不做**）

见下方 Consequences。理由：本次先止血，且整车替换要动 pack 注入点，回归面比 bug 本身大。

## Options Considered

| 选项 | 收益 | 代价 / 风险 |
|---|---|---|
| **A. 按契约修解析 + 随行补端点**（采用） | 改动限于 2 文件、57 行；不碰 pack 注入点；把「为什么」写进注释 | 仍是自己的一份实现，与原生 `AccessModal` 的后续漂移风险保留 |
| B. 整车复用宿主 `shared/access_modal/` | 契约同源、原生升级自动跟随；能消掉重复实现债 | 要改 pack 注入 + 传`urls`/对象；回归面覆盖整个弹窗；原型树里那份的正确实现也得一并处置 |
| C. 把正确那份（`vue/eln/`）注册进 entryList 上线 | 复用已有正确实现 | 它同样是自己的一份，只是没踩坑；治标不治本，且要维护两个注册入口 |

## Consequences

**变容易的**
- 行级 access 的三处原生契约（元组 / AMS attributes / collection POST）都落成了注释与代码同源的真源；
- 验收脚本 `_eln_access_addmember.js` 覆盖了「真点新增 + 真点移除复原」，写路径从此有回归网。

**变难的 / 保留的债**
- ⚠ **重复实现债未清**：`vue/eln/components/overlays/RowActionModal.vue` 仍未注册 entryList，
  两份实现并存。建议后续做选项 B（整车复用原生 `AccessModal`）时一并处置。
- ⚠ **契约靠注释保鲜**：`user_roles` 的 `.reverse` 次数、AMS adapter 形状都是宿主实现细节，
  上游一改这里就悄悄坏。护栏已在，但本质是「抄契约」的固有成本——这正是选项 B 的动机。

## 验证

- 静态：成员角色 `selected=1/"Owner"`、`optionCount=8`；`addUserOpts=[Admin, dy@qq.com, qj@qq.com, hpxing@localhost]`（已排除已指派）；`addRoleOpts` 同 8 项；`error=null`。
- 端到端：真点添加 → `POST /access_permissions/projects?id=34` → 200，成员 `1→2`；真点移除 → 复原 `2→1`；**404 出现 = false**；`pageErrors=(无)`。
- 资产：定向webpack digest `eln_project_list-b8a90705…`。