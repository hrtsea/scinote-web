#02 — 筛选面板 6 处日期换日历

Status: ready-for-agent
Blocked by: 01

## 问题

ELN 项目列表的筛选面板有 6 处原生 `<input type="date">`：开始日期从/ 至、截止日期 从/ 至、归档日期 从/ 至。

这些是**纯筛选条件**，值经`buildListQuery()` 直接塞进 `URLSearchParams` 发给后端（`Lists::ProjectsService#filter_project_records`），消费方吃的**就是字符串**。

## 目标

6 处换成 01 建好的 `DateField`，`v-model` 绑定的 ref **一行不改**（现状就是字符串）。

## 涉及位置

| 日期字段 | store 里的键 |
|---|---|
| 开始日期 · 从 / 至 | `ui.filters.start_date_from` / `start_date_to` |
| 截止日期 · 从 / 至 | `ui.filters.due_date_from` / `due_date_to` |
| 归档日期 · 从 / 至 | `ui.filters.archived_on_from` / `archived_on_to` |

每处替换时保留既有的 `data-e2e`（现状筛选面板已有 9 个 `data-e2e`；`fp-start-from` 与 `fp-due-from` 挂在日期上）。`data-e2e` 形态为 `fp-*`，日期字段沿用同一前缀。

## 硬约束

1. **`buildListQuery()` 一行不改** —— 它遍历 6 个键名并`p.set('filters[...]', f[k])`，值的格式没变就不该碰。动它就等于改了后端契约。

2. **三组「从 / 至」保持两个独立选择器形态**（用户已裁决）。不引入 range 模式，不把两个 ref 合成一个数组 —— 那个改动会连带 `resetFilters()` 和 `applyFilters()`。

3. **`resetFilters()` 必须把 6 个日期一并清空**。store 里 `ui.filters` 与 `filters` 的初始值各有一份 6 个日期键（全为 `''`），两处都要确认清空逻辑覆盖到。

4. **归档日期那组只在归档态视图可见** —— 保持既有显隐条件，不要顺手改。

5. **`archived_on_*` 的键名不要与 `start_date_*` 混用**。后端按不同字段过滤，串了会筛出错误结果且无报错。

## 验收

- 筛选面板打开，6 处显示日历占位/图标，不再是分段数字框
- 点开任一日期 → 弹层出现完整 6 行月历，**未被筛选面板边界裁剪**（这一条直接验 01 的 teleport 约束）
- 点某天 → 输入框显示 `YYYY-MM-DD`，弹层自动关闭
- 手动键入 → 归一为 `YYYY-MM-DD`
- 点重置 → 6 处日期全空、占位回来
- 设定开始日期后刷新列表 → **抓网络请求断言 `filters[start_date_from]=2026-10-11` 原样发出**
- 列表确实按该日期过滤（行数变化），证明不是「看着变了但没生效」
- 0 JS 错误、0 失败请求

## 备注

- 筛选面板的入口是项目列表页（`/eln_project_list`，生产页）。
- `data-e2e` 覆盖已够（9 个），不需要额外补。