# ADR-0051 — 实验详情页可编辑化（信息 / 目的 / 方法 / 状态 + DOE 设计变量 CRUD）

- 状态：Accepted（2026-10-13）
- 上游：截图评审发现 `/experiments/:id/eln_exp_detail` 的「实验信息 / 实验目的 / 实验方案与方法」三块全只读、「编辑实验信息」与面板内「编辑」两按钮无 `@click`；`eln_ui_design_variables` 已有 4 行真数据但只读渲染。诉求：让这些可编辑、并建立相应数据表承载。
- 设计流程：ask-matt → grill-with-docs → grilling（两轮共识，前沿已空）。

## 1. 盘问决策表（两轮）

### 第 1 轮（6 问）
| # | 问题 | 选 | 推荐 | 结论 |
|---|------|----|------|------|
| Q1 | 可编辑字段范围 | c（7 格全开） | a（6 业务字段） | **收口为 a**：`所属项目`/`任务进度` 原生无承载，见 §2 |
| Q2 | 状态怎么编辑 | a（表单内状态下拉） | a | 走原生 `TimeTrackable#status=` 三态机 |
| Q3 | 编辑交互形态 | a（弹窗表单） | a | 与项目详情「编辑项目信息」同款（mask+modal+PATCH+reload） |
| Q4 | 「等」还包括什么 | b（DOE 设计变量 CRUD） | a | **做 b**：变量表行级增改删 |
| Q5 | 数据表落点 | a（不建新表） | a | 复用 `eln_ui_experiment_profiles` + `eln_ui_design_variables` |
| Q6 | 编辑权限口径 | a（MANAGE） | a | `ExperimentPermissions::MANAGE`，与 design 子页签显隐同源 |

### 第 2 轮（3 问，收口 + DOE 范围）
| # | 问题 | 选 | 推荐 | 结论 |
|---|------|----|------|------|
| Q7 | 所属项目 / 任务进度保持只读？ | a | a | 二者派生/无承载，保持只读 |
| Q8 | DOE CRUD 范围 | a（仅变量表行级 CRUD） | a | AI 按钮（场景A/B、贝叶斯、一键生成）保持占位，需后端 AI 服务另立项 |
| Q9 | DOE 行排序 | a（append 末尾，不拖拽） | a | `position` 自增，无重排 |

## 2. 冲突收口（Q1=c 的真实约束）

Q1=c 字面含「所属项目 / 任务进度」两项，但真源层面无法直接编辑：
- **所属项目**：原生 `experiments` 的 update **不接收 project_id**；改项目 = 把实验 re-parent 到另一项目，原生无此能力、也无承载面。硬做需另写 re-parent 端点，语义重、风险高 → **保持只读**（来自 `projects.name`，与面包屑同源）。
- **任务进度**：是 `已完成任务数 / 总任务数` 的**派生值**，不是字段，无写入口 → **保持只读**。

实际可编辑集 = 选项 a 的 6 字段 + Q2 状态：
`业务编号(business_code) / 名称(name) / 负责人(profile.owner_user_id) / 计划完成(due_date) / 目的(purpose) / 方法(method) + 状态(status)`。

## 3. 数据契约

### 3.1 承载面（不建新表，Q5=a）
- 原生 `experiments`：`name` / `due_date` / `status`（虚拟属性，`TimeTrackable` 写 `started_at`/`done_at`）。
- `eln_ui_experiment_profiles`（已存在，1 行在用）：`business_code` / `owner_user_id` / `purpose` / `method`，经 `ExperimentProfile.upsert_for!` 幂等写入。
- `eln_ui_design_variables`（已存在，4 行真数据）：`name` / `var_type` / `range_min` / `range_max` / `unit` / `constraint` / `position`。

### 3.2 payload 新增字段（`ExpDetailPayload#call`）
- `editInfo`：原始可编辑值 `{ business_code, name, owner_user_id, due_date, purpose, method, status }`（`status` 取 **trackable 形态** `not_started/in_progress/done`，供表单直发）。
- `memberOptions`：`[{id, name}]` = 实验所属项目 `team.users`（负责人下拉真源；当前 owner 不在列表内也保留）。
- `expDesignVars` 每项**补原始字段** `range_min` / `range_max` / `unit`（display 仍用组装 `range`，编辑表单读原始字段）。

## 4. 后端端点

### 4.1 `ExpDetailController#update`（PATCH `experiments/:id/eln_exp_detail`）
- 闸：`return render_403 unless can_manage_experiment?`（与 design 子页签同源）。
- 强参数 `experiment: [:name, :due_date, :business_code, :owner_user_id, :purpose, :method, :status]`。
- 事务内：原生 `name`/`due_date` 直接 `update!`；`status` 经 trackable 形态直发 `exp.update!(status:)`；profile 字段 `ExperimentProfile.upsert_for!(exp, profile_attrs)`。
- 返回**全量 payload**（前端 `window.location.reload()` 同源，不解析 body）。
- 校验失败 `rescue RecordInvalid → 422 {error}`。

### 4.2 `ExpDesignVariablesController`（create/update/destroy）
- 路由：`POST experiments/:experiment_id/eln_exp_design_variables`、`PATCH/DELETE .../:id`。
- 闸：`Experiment.readable_by_user` 取实验 + `permission_granted?(MANAGE)` → 否则 403/404（跨实验 id 不泄漏存在性）。
- `var_type` 强参数白名单 `float/integer/categorical`（模型 validates inclusion）。
- `position`：创建时 `max(position)+1`（append，Q9=a）。
- 返回 `{ expDesignVars: [...] }`（与 index 同源 shape，前端就地 `replaceList` 不跳页）。

## 5. 前端

- `store/ui.js` 新增 `canManageExperiment: false` / `memberOptions: []` / `editInfo: {}`；entry 从注入 `canManageExperiment` / `memberOptions` / `editInfo` 写入。
- `ExperimentDetail.vue`：
  - 页头「编辑实验信息」+ 信息面板「编辑」两按钮加 `v-if="canManage"` 闸门（此前是死按钮）。
  - 「实验信息」编辑弹窗：7 字段（编号/名称/负责人下拉/计划完成 date/目的 textarea/方法 textarea/状态 select），初值取自 `ui.editInfo`；提交 `sendForm(PATCH)` → `window.location.reload()`。
  - 设计变量表行级：每行加「编辑 / 删除」、表头加「新增变量」（`v-if="canManage"`）；弹窗字段 `name/var_type/range_min/range_max/unit/constraint`；提交 create/update/destroy → 成功 `replaceList(expDesignVars, res.expDesignVars)`（不跳页，留在 design 子页签）。
- AI 按钮（场景A/B 切换、重新计算贝叶斯、一键生成验证任务）保持占位（Q8=a，另立项）。

## 6. 验证
- `exp_detail_test.rb`：守 `editInfo`/`memberOptions` 字段存在与口径、`expDesignVars` 含原始字段；DOE CRUD 正反例（MANAGE 闸、跨实验 id 404、var_type 非法 422、append position）；update 事务后原生字段 + profile 落库。
- 真机 prod:3000 + Edge：三块可编辑弹窗可开可存、DOE 增改删即时刷新、非 MANAGE 角色看不到编辑按钮。
- 全套既有 7 errors+1 failure 与本次无关（隔离重跑已证）。
