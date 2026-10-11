#05 — 旧 AG Grid 渲染器 2 处日期换日历

Status: ready-for-agent
Blocked by: 01

## 问题

项目列表的**旧 AG Grid 渲染器**里，行操作弹窗有 2 处原生 `<input type="date">`（开始日期 / 截止日期），字段名是 `form.startDate` / `form.due`。

这与 ticket 03 处理的**新架构** `components/overlays/RowActionModal.vue` 是两个不同文件、两条不同的加载链（一个走 AG Grid `cellRenderer`，一个走 Vue3 `createApp`）。

不处理它，两个列表版本（`/eln_project_list` 生产页 vs `/eln_project_list_v1` 比对页）会给出**不同的日期录入体验**。

## 目标

这 2 处换成 01 建好的 `DateField`，行为与新架构版本一致。

## 涉及位置

旧渲染器 `renderers/row_action_modal.vue`，被 `renderers/row_menu_renderer.vue` 以 `components: { RowActionModal }` 方式注册进 AG Grid 单元格渲染器。

## 硬约束

1. **🔴 弹层在 AG Grid 单元格内必须不被裁剪**。AG Grid 自带高层级弹层（dropdown / popup 组件的 z-index），而单元格渲染器处在 grid 的 overflow 上下文里。这是本 ticket 比其他 4 个**更难**的地方 —— 必须实测确认 teleport 到 `body` 后弹层能盖住 AG Grid 的弹层层，且不被 grid 边界切掉。

2. **`form.startDate` / `form.due` 的初值来源保持**。这个弹窗的初值走 `rowData()` 取摊平后的行数据再 `.toString().slice(0, 10)`。**不要顺手改这块取值逻辑** —— 上一轮刚修过「`row.attributes` 恒为 `undefined`」的 bug（`DataTable#formatData` 摊平 AMS 数据），改坏会回退那个修复。

3. **提交 payload 不变**：仍是 `start_date: this.form.startDate || null`。

4. **`data-e2e` 已有 20 个**（够用），保留既有的 `e2e-IF-rowAction-start` / `e2e-IF-rowAction-due`。
   ⚠ 但注意：03 处理的新架构弹窗里也有同语义的字段，Playwright 定位时要用**页面**区分，不能只靠名字。

5. **`RowActionModal` 的权限判定逻辑一个字不动**。上一轮刚补齐的三层判定（`last_owner` / `manage_users_assignments` / `inherit_message`）与日期无关，别在改模板时误伤。

## 验收

- 在旧版列表页打开行操作弹窗 → 日期字段显示日历
- 点开日历 → 弹层出现完整月历，**既未被 grid 边界裁剪、也未被 AG Grid 自身弹层盖住**
- 选日期 → 输入框显示 `YYYY-MM-DD`，弹层关闭；保存后列表行日期列不再是 `—`
- 清空 → 值变 `''`
- **回归**：该弹窗的成员权限三层判定仍生效（最后一个 Owner 的角色不可改、继承权限不可改）
- 0 JS 错误、0 失败请求

## 备注

- 这是**最后一批**，也是唯一在 AG Grid 上下文里的。做完这批，17 处全部收口，两个列表版本体验一致。
- 若 teleport 在 AG Grid 内实测失败，不要退回到原生 input —— 那是把spec 的目标砍一半。此时应改为在弹窗挂载点（`row_menu_renderer` 层级）而非 body 上挂弹层容器，并把结论回写进本 ticket。