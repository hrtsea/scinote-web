# ADR-0048：eln_workbench 改版为「个人行动工作台」（只显示需要处理的事）

- 状态：已接受（2026-10-12 grilling Q1~Q15，用户逐条拍板）
- 关联：ADR-0045（workbench 并入 eln_ui）、ADR-0029 / ADR-0032（审批名单口径）、
  DEC-003（任务关闭审核）、REQ-DASHBOARD / SCN-DASH-1~8（原仪表盘规格，本ADR 局部作废）

## 背景与诉求

用户原话：「eln_workbench 打造为个人工作台，每天从这里开始：这里只显示需要处理的事，
来自你能看到的所有数据库，查看待办事项、需要进行的审批事项、正在进行的项目」。

现状（ADR-0045 合并时的六块仪表盘）：meta + 3 张 KPI 卡 + 个人待办 + 任务状态分布 +
小组汇总 + 快捷入口。它是**统计仪表盘**（回答"有多少"），不是**行动工作台**
（回答"我现在该做什么"）。且两处口径已腐烂：

1. 待办里的「我的任务」**不过滤完成态与归档**（`my_open_modules` 无 state/archived 条件），
   已完成任务与结题项目里的任务照样占位（`workbench_payload.rb:371-377` 旧实）；
2. 待审批只接 ResourceApplication 一条，且用「同队 + 非本人」旧推断口径 —— 真闸门
   `ResourceApprovalPolicy` 早已改为 `ProjectApprover` 显式名单（fail-closed，
   `resource_approval_policy.rb:68-75`）。工作台会出现「列了 3 条、点进去 2 条没权限审」；
3. `TaskCloseRequest`（任务关闭待审）、`ReceiptVerification`（到货待验）有表、有 scope、
   有闸门，却未进工作台 —— 「来自所有数据库」名不副实。

## 决策（grilling 结论，逐条）

| # | 决策 |
|---|---|
| Q1 | **全删统计块**：KPI 卡 / 任务状态分布 / 小组汇总 / 快捷入口全部移除。只留 页头(问候+角色徽标) + 通知铃铛 + 三大行动区。统计数字在项目列表页/资源中心已有承载，工作台不复述 |
| Q2 | 待办只收**未完成**任务（`state=uncompleted` ∧ 状态非 final），**逾期置顶红标**（`due_date` 早于今天；今天到期不算逾期但排最前） |
| Q3 | 审批收**全部四条真源**：资源申请(初审/终审)、任务关闭审核、到货验收（以上三条「待我审」）+ 我的申请待验货（申请人侧，并入待办区）。统一改按名单真源判定，修掉分叉 |
| Q4 | 「正在进行的项目」= `ProjectListScope.participated`（参与 = Project 级 UA ∩ team ∩ 可读 ∩ active ∩ 非模板）——与「参与项目」KPI 同一真源，卡片/列表条数必须逐位相等 |
| Q5 | 「所有数据库」边界 = **当前 team 内**（`readable_by_user ∩ current_team`）。工作台保持 `check_team_membership` 闸门；跨 team 聚合不动（权限模型承重墙） |
| Q6 | **不改宿主 root**（现为 `dashboards#show`）。「每天从这里开始」靠 ELN 侧栏「工作台」首位入口 + 页面自身定位达成 |
| Q7 | 三区「查看全部」**只接已有承载面**：项目区→项目列表页带成员筛选；资源申请分组→资源中心 `?tab=apply`；待办区无跨项目任务清单页⇒**不给链接**只显示「共 M 条」；任务关闭/到货验收无跨项目承载面⇒只计数 |
| Q8 | 待办/审批**平铺 + 类型标签**；待办区内逾期置顶→截止近→远；审批区内按来源分三小段（资源申请/任务关闭/到货验收）各按提交时间倒序 |
| Q9 | 项目区每项 = 名称 + 状态徽标（未开始/进行中/已完成，由 `started_at`/`done_at` 推导，复用 `project_list_payload#status_of` 同款逻辑）+ 我的角色（负责/参与，双轨）+ 任务摘要（我在该项目的未完成任务数） |
| Q10 | 三区上限均 **20 条**；空态显式留白（「暂无待办事项」等），不编演示值 |
| Q11 | 列表项**全部可点**，URL 由 payload 用宿主/引擎真实 path helper 下发（铁律：前端不写死宿主路由）：任务→`eln_task_detail`；申请/验货→`eln_res_apply_detail`；项目→`project_eln_detail` |
| Q12 | payload 契约为**平铺数组 + 每条带 `kind`(稳定键) 与 `type`(展示标签)**：`{ meta, todos, approvals, projects, links, totals }`。前端按 kind 分组、按 type 展示，分组标签不硬编 |
| Q13 | **统一纵排三区**（页头+铃铛 → 待办 → 审批 → 项目），全宽单列，移动端天然友好 |
| Q14 | 三区**全链路排除归档**：待办任务要求 项目∩实验∩任务 均未归档；审批排除归档项目下的单子；项目区本就是 `archived:false` |
| Q15 | 审批项**只查看+跳转**，批准/驳回/验货动作仍在详情页（有原因输入、审计轨迹、权限复核）。工作台是「发现器」不是「操作台」——避免把闸门与审计逻辑复制第二份 |

## 数据源口径（单一真源映射）

| 区 | 真源 | 判定 |
|---|---|---|
| 待办·任务 | `MyModule` × `UserAssignment` | 指派给我 ∧ `state=uncompleted` ∧ 状态非 final ∧ 项目/实验/任务未归档 ∧ 项目 ∈ readable ∩ team |
| 待办·待验货 | `ReceiptPendingBook.for_applicant` | 我申请 ∧ `project_approved` ∧ 材料类 ∧ 未达验货阈值（Ruby 侧再筛 team ∧ 未归档，不动该类） |
| 审批·资源申请 | `ResourceApplication` × `ResourceApprovalPolicy` | 项目 ∈ `approvable_project_ids(user, team)` ∧ status ∈ (submitted, group_approved)；阶段标签取 `pending_stage`（group=待初审 / project=待终审） |
| 审批·任务关闭 | `TaskCloseRequest.pending` × `TaskCloseWorkflow` | 项目 ∈ **本ADR 新增的** `TaskCloseWorkflow.reviewable_project_ids(user)`（Project 级 Owner UA，与 `reviewer?` 闸门逐字同口径——判一处，别在两处各判一次） |
| 审批·到货验收 | `ResourceApplication` × `ReceiptVerification` | 项目 ∈ `verifiable_project_ids(user, team)` ∧ `project_approved` ∧ 材料类 ∧ `!completed_threshold_reached?`（与 ReceiptPendingBook 同一收口规则） |
| 项目 | `ProjectListScope.participated` | 见 Q4；三态复用 `status_of` 逻辑；角色用 `responsible_condition` |

⚠ **任务关闭的「项目负责人」只认 Project 级 Owner UA 轨**（`TaskCloseWorkflow.reviewer?`
的既有口径，OPEN-1 未裁决前的取法）——不放宽到 supervised_by 轨，否则工作台会列出
点下去被闸门 422 的单。放宽属 TaskCloseWorkflow 自身决策，不在本ADR 范围。

## Payload 契约

```ruby
{
  meta:    { greeting, role, updatedAt, notice },        # statusMachine 随分布图删除
  todos:   [{ kind: 'task'|'receipt_pending', type:, title:, due:, overdue:, status:, tone:, to: }],
  approvals:[{ kind: 'resource_application'|'task_close'|'receipt', type:, title:, due:, status:, tone:, to: }],
  projects:[{ name:, status:, statusLabel:, role:, taskSummary:, to: }],
  links:   { projectsAll:, resourceApplicationsAll: },   # 无承载面 ⇒ nil（显式留白）
  totals:  { todos:, approvals:, projects: }             # 真实总数（超 20 时「共 M 条」用）
}
```

- 排序：todos = 逾期置顶 → due 升序(NULLS LAST) → 创建倒序；approvals 按
  (资源申请 → 任务关闭 → 到货验收) 固定段序、段内提交时间倒序；projects =
  `started_at DESC NULLS LAST, id DESC`。
- 上限 20/20/20（Q10=B）。
- 色值/文案/链接全部 payload 下发，组件不硬编（沿用既有铁律）。

## 前端结构（Workbench.vue 重写）

单列三区 + 页头 + 通知铃铛（铃铛下拉逻辑原样保留，仍走 `/eln_notifications` 实时端点）：

1. **待办事项**：平铺列表，每条 = 类型标签 + 标题 + 截止(逾期红) + 状态标签；可点跳 `to`；
   头部「共 M 条」，无「查看全部」（无承载面）。
2. **审批事项**：按 `kind` 分三小段，段头 = 段名（取该段首条 `type`）+ 可选「查看全部」
   （仅 resource_application 段有，取 `links.resourceApplicationsAll`）；条目同待办形状。
3. **进行中的项目**：每条 = 项目名 + 状态徽标 + 角色徽标 + 任务摘要；可点跳项目详情；
   头部「查看全部」取 `links.projectsAll`。

入口 `entries/workbench.js` 覆盖策略不变（meta 浅合并、数组整体替换），需把
kpis/dist/groups/entries 五个键换成 todos/approvals/projects/links/totals。
mock.js 的六块画布演示值同步换为新形状（原型独立跑仍可渲染）。

## 后果

- **作废**：SCN-DASH-1~8 中 KPI 卡（SCN-DASH-8 下钻）/分布图/小组汇总相关规格；
  `workbench_test.rb` 中对应断言整体重写。
- **牵连**：`mock.js` 工作台六块、`entries/workbench.js` 覆盖键、e2e 基线不受影响
  （6 页基线不含 `/eln_workbench`）。
- **不作**：不改宿主 root（Q6）、不建跨项目任务清单页（Q7）、不做内联审批（Q15）、
  不动 TaskCloseWorkflow 闸门口径（只新增 `reviewable_project_ids` 供工作台复用）。
- 原 OPEN-WORKBENCH-1（UserGroup 无 leader 列）随小组汇总删除而消解；OPEN-WORKBENCH-2
  （通知只报条数）随铃铛保留而维持；OPEN-WORKBENCH-4（四角色差异化布局）维持未裁决。

## 验证计划

1. `addons/eln_ui/test/workbench_test.rb` 重写：四源各至少一条正/反断言
   （含「名单外用户看不到任务关闭待审」的 fail-closed 反例、归档排除反例）；
2. 容器内单 entry 重建 `eln_workbench` + precompile + restart；
3. Playwright 真机（prod :3000，真实 Warden 会话）：三区渲染、逾期红标、链接 digest、
   空态（切到无数据用户或临时清数据的视角用现有 4 用户库验证差异）。
