#04 — 资源中心 4 处日期换日历（含区间反了警告）

Status: ready-for-agent
Blocked by: 01

## 问题

资源中心有 4 处原生日期输入，分两组「从 ~ 至」：台账筛选 2 处、消耗记录筛选 2 处。

这 4 处的值会进**网络请求参数**（`range_from`）与**导出请求**，且分属两个独立 `ref` 对。现状有个体验缺陷：**起始晚于截止时不报错**，用户得到一个空结果列表，不知道是筛选条件反了还是真的没数据。

## 目标

4 处换成 01 建好的 `DateField`，并在「起始 > 截止」时给出**可见警告**（不阻断）。

## 涉及位置

| 组 | ref | 消费方 |
|---|---|---|
| 台账筛选 | `ledgerFilterFrom` / `ledgerFilterTo` | `params.set('range_from', ...)`、台账查询 payload `range_from` |
| 消耗记录筛选 | `filterFrom` / `filterTo` | `params.set('range_from', ...)`、消耗查询 payload `range_from` |

两组的重置函数（`resetLedgerFilter` / `resetConsumeFilter`）必须继续把对应两个 ref 清空。

## 硬约束

1. **保持两个独立选择器形态**（用户已裁决）。**不引入 range 模式** —— 那会把两个 `ref` 变成一个数组，`resetLedgerFilter` / `resetConsumeFilter` / 两处 `params.set` 都要改，回归面显著变大。

2. **区间反了 = 警告，不是阻断**。给输入框加 `invalid` 视觉态 + 一段说明文案，但：
   - **不清空**任一值
   - **不阻止**查询/刷新
   - **不阻止**导出
   理由：条件反了通常来自误点，用户要自己决定改起始还是改截止；硬阻断会把「改一个值」变成「清空两个值重填」。

3. **`range_from` 参数名与格式不变**。导出 CSV 必须仍反映当前筛的区间 —— 这是资源中心的核心用途。

4. **🔴 `data-e2e` 必须补齐** —— 现状 `ResCenter.vue` 的 `data-e2e` 数量为 **0**。两组的起始日期各需新增一个（建议 `rc-ledger-from` / `rc-consume-from`），否则本 ticket 的验收无法被 Playwright 定位。

5. **弹层不被资源中心筛选条裁剪**。筛选条本身有布局上下文，需确认 teleport 生效。

## 验收

- 资源中心加载，4 处显示日历
- 台账组：设定区间 → **抓请求断言 `range_from=2026-10-01` 与 `range_to`（或等价参数）正确**
- 消耗组：同上
- 点导出 → 导出请求携带同一区间（CSV 内容反映筛选）
- **区间反了**：台账组设起始 `11-10` / 截止 `11-01` → 出现可见警告态；**列表仍能刷新**（不阻断）、**导出仍能点**（不阻断）、两个值都没被清空
- 修正为正常区间 → 警告消失
- 点重置 → 两 ref 清空、警告消失
- 0 JS 错误、0 失败请求

## 备注

- `ResCenter.vue` 属**独立 webpack entry**（`eln_res_center` / `res_center.js`），与项目列表、预定页各自打包。编译时 `ENTRIES` 要一次带上 `eln_res_center`。
- `ResCenter.vue` 用 `rc-date` class（有专门的紧凑高度），`DateField` 的 `size` 要能对齐它。
- 上轮 E2E 验收已确认资源中心页面正常渲染（DOM 长度 54999），改动后不能回退。