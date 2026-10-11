#03 — 新建/编辑弹窗与预定表单 5 处日期换日历

Status: ready-for-agent
Blocked by: 01

## 问题

三个弹层/表单共 5 处原生日期输入：新建项目弹窗 2 处、行操作弹窗 2 处、设备预定表单 1 处。

其中设备预定表单有个**派生显示**：`· 周{{ weekdayOf(form.date) }}` —— 日期一变，后缀要实时跟着变。

## 目标

5 处换成 01 建好的 `DateField`，`v-model` 与派生逻辑一行不改。

## 涉及位置

| 组件 | 字段 | 消费方 |
|---|---|---|
| 新建项目弹窗 | `form.start` / `form.due` | 提交 payload `start_date` / `due_date` |
| 行操作弹窗（新架构） | `ui.rowAction.form.start` / `.due` | 同上 |
| 设备预定表单 | `form.date` | `weekdayOf()` 派生后缀 + 提交 payload |

## 硬约束

1. **`weekdayOf()` 一行不改**。它吃字符串（`new Date(s + 'T00:00:00')`），前提是「字符串就是本地日历日」。这正是 01 禁`toISOString` 的原因。
2. **清空日期时后缀必须消失**，不能显示「周undefined」。现状 `weekdayOf` 对非法输入返回 `''`，模板渲染成「周」，属于脏字符 —— 顺带修掉：空值时整个后缀不渲染。
3. **预定日期默认今天**的行为保持。现状 `BookingForm` 初始化时 `form.date = ymd(TODAY)`，走既有工具函数，不改成 `new Date().toISOString()` 之类。
4. **提交 payload 的日期格式不变**：`start_date` / `due_date` 仍是 `'YYYY-MM-DD'` 或 `null`。后端字段口径不动。
5. **`data-e2e` 必须补齐** —— 这是本 ticket 的**测试前置条件**，不是额外负担：
   - 设备预定表单 `BookingForm.vue` 现状 `data-e2e` 数量为 **0**
   - 行操作弹窗现状 23 个（够用）
   - 新建项目弹窗现状 3 个（够用）
   预定表单的日期字段要新增一个 `data-e2e`（建议 `bf-date`），否则 03 的验收无法被 Playwright 定位。

## 验收

- 三个弹层/表单的日期字段都显示日历，弹层不被弹窗边界裁剪
- 新建项目：选起止日期 → 提交 → 列表新增行的日期列不再是 `—`
- 行操作弹窗：选日期保存 → **刷新页面后列表行日期列不再是 `—`**（这一条验真实持久化，不只是弹层里变了）
- 预定表单：点选新日期 → 相邻「· 周X」后缀**同步改变**为正确周几
- 预定表单：清空日期 → 后缀消失，**不出现「周undefined」或悬空的「· 周」**
- 预定表单：不操作直接提交 → 日期是今天（默认行为未破）
- 手动键入非法串（如 `2026-13-45`）→ 组件归一为 `''` 或拒绝，**不发出脏值**
- 0 JS 错误、0 失败请求

## 备注

- 行操作弹窗有**两个版本**：新架构的 `components/overlays/RowActionModal.vue`（本 ticket 处理）与旧 AG Grid 渲染器里的 `renderers/row_action_modal.vue`（ticket 04 处理）。别改错文件 —— 上一轮「补访问权限三判定」改的是后者。
- `BookingForm` 属设备预定页，走 vue-router 懒加载，只在 `eln_workbench` 那套 SPA 里；`ResCenter`（ticket 04）属独立 entry。编译时 `ENTRIES` 需分别带上。