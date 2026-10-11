#01 — 建 DateField 薄封装组件

Status: resolved

## 落地后的实测发现（比上面的规格更准，务必读）

### 🔴 1. scoped 对 `input-class-name` 无效 —— 输入框样式必须非 scoped
`input-class-name` 挂上去的 `<input>` 是 **VueDatePicker 内部渲染**的，只带 VueDatePicker 自己的
`data-v`，没有 DateField 的 `data-v` ⇒ **scoped 选择器永远匹配不到**。
症状极具欺骗性：不是「样式全丢」，而是看起来「部分生效」——
三档 `size` 全渲染成同一个 38px、invalid 描边不变红、bare 背景不透明，
而 `border-radius` / `box-sizing` 却看着生效（那些是 VueDatePicker 默认就有的值）。
**第一版就写进了 scoped 段，19/23 项验证红。**

⇒ 输入框与浮层两段样式都必须放在 `<style>`（无scoped），用 `.date-field__input` /
`.date-field-menu` 前缀限定作用域。清空按钮（自己模板渲染的）可以留在 scoped。

### 🔴 2. padding 必须四边分别写，不能用简写
`padding: 0 12px` 会把 VueDatePicker 图标位与自绘清空按钮的padding 一起重置
⇒ 日历图标直接压在占位文字上（「选empty」变成图标叠字）。
改为 `padding-left: 30px !important; padding-right: 32px !important`（按档位不同）。

### 🔴 3. `.dp__input.dp__input_icon_pad` 特异性高于自定义类名
即使作用域对了，盒模型（`height` / `border` / `background`）也会被它盖掉 ⇒ 必须 `!important`。
宿主 `shared/date_time_picker.vue` 的 `.no-border` / `.only-time` 是同一套既定做法。

### 🔴 4. `toISOString` 的坑比「每天减一天」更微妙（负向验证才发现）
原以为「东八区每天减一天」，实测发现 **VueDatePicker 传给 `onPick` 的 Date 不保证是本地午夜**：
- 非今天 → 本地午夜 `00:00`（实测 `'2026-10-27T16:00:00.000Z'` 而本地是 10-28）⇒ 误用 `toISOString` **必减一天**
- 某些情形 → 当天正午 `12:00`（`'2026-10-28T04:00:00.000Z'`）⇒ `toISOString` **恰好不减**

⇒ **该 bug 不是每次复现**。注入 `toISOString` 后测 5 个日期（2/9/16/23/28），
**4 个偏移一天、只有 2 号不偏移**（当天=2 号且时刻特殊）。
⇒ 结论：**验收必须多点采样**。只点一个日期有可能恰好落在不偏移的情形上，
断言就恒真了 —— 我第一版就是单点采样，跑出来 25/25 全绿，差点以为防线有效。

### ⚠ 5. 验证脚本自身踩的两个坑（都不是组件的问题）
- `grep -c` 数的是**行数**，产物是压缩后单行 ⇒ 永远是 1。别用它判断「代码有没有进包」，
  要 `grep -o ... | wc -l` 或直接看上下文片段。
- 日部分比较必须 `parseInt`：`'02' !== '2'`（前导零）。字符串比会把**正确实现也报成失败**。

### v7 prop 名的坑
是 `menuClassName` / `inputClassName`，kebab 写成 `menu-class-name` / **`input-class-name`**
（不是 `input-class`）。写错 prop 名不会报错，只是**静默不生效**。

## 验证结果

**26/26 全绿**（探针跑真实浏览器，非静态检查）：

| 组 | 覆盖 |
|---|---|
| A（6） | 五种初值形态归一：空串 / Date 对象 / 非 YMD 串（判非法）/ 合法 YMD / **溢出日期 2026-02-31 被拒** / ISO 带时间 |
| B（6） | 弹层打开、**teleport 到 body**、`menu-class-name` 锚点挂上、完整可见未裁剪、6 行月历 42 格、**5 个日期多点采样无时区偏移**、字符串类型、YMD 形状、回显一致、auto-apply 关闭 |
| E（3） | 清空按钮出现、清空后值 `=== ''`（不是 null/undefined）、占位回来 |
| F（3） | 三档高度 28/30/36 并存、invalid 描边 `#CE0C24`、bare 背景透明 |
| H（2） | 左侧 padding 够放下图标（不压占位）、右侧够放下清空按钮 |
| G（1） | 0 JS 错误 |

**负向验证已做并通过**：注入 `toISOString` ⇒ B9 立即失败（点9→得08、点16→得15…），
还原后恢复全绿。**这条断言确实在守防线，不是恒真。**

## 备注

- 这是本 effort 的**承重件**：01~04 全部依赖它。契约一旦定错（比如改成吐 `Date` 对象），
  后面 4 个 ticket 全要返工。
- 判据是「17 处调用方能不能一行不改」，不是「组件本身功能全不全」。
- **验证脚本没留在仓库**（临时探针 + 一次性 webpack 配置，验收后已删），
  符合本仓库「不新建测试基础设施」的约定（见 ticket 06：正式验收扩展既有Playwright 脚本）。
  26 项断言的逻辑已迁移进 ticket 06 的场景清单。

## 问题

ELN 有 17 处日期输入用浏览器原生 `<input type="date">`，用户只能逐字符键入、且依赖本机日期格式（`2026/10/11` vs `10/11/2026` vs `2026-10-11` 混用时无法判断月/日），也完全看不到月份全貌。

项目里已有成熟日历库 `@vuepic/vue-datepicker@^7.4.1`（宿主原生页在用），ELN 侧从未接入。

## 目标

在 ELN 新架构下建一个薄封装组件，作为全部 17 处日期输入的唯一入口。契约收敛为**日期字面量字符串** `'YYYY-MM-DD'`（空 = `''`），与今天原生 input 的 `v-model` 值**完全一致**，所以 17 处调用方的 data 层一行不改。

**这个 ticket 只建组件本身，不改任何调用方。**

## 规格

放在 ELN 新架构的 components 目录（与 `AppIcon.vue` 同级）。

### props

| prop | 类型 | 默认 | 说明 |
|---|---|---|---|
| `modelValue` | `String \| null \| undefined` | `''` | 日期字面量 `YYYY-MM-DD`。允许 `''` / `null` / `undefined` |
| `placeholder` | `String` | `''` | 空值时显示的提示 |
| `disabled` | `Boolean` | `false` | 禁用 |
| `clearable` | `Boolean` | `true` | 是否显示清空按钮 |
| `size` | `String` | `'md'` | 对齐既有不同高度输入（`rc-date` / `bf-bare` / `field-input`） |
| `invalid` | `Boolean` | `false` | 区间反了等错误视觉态 |
| `dataE2e` | `String` | `''` | 透传到根元素，Playwright 定位用 |

### emits

- `update:modelValue`：值同 `v-model`（`'YYYY-MM-DD'` 或 `''`）
- `change`：同上，供需要副作用的场景

### 硬约束（违反会导致静默 bug）

1. **🔴 字符串转换必须复用 ELN 已有的本地时区成对函数**：`equipment.js` 里的 `ymd(date)`（用 `getFullYear()/getMonth()/getDate()`）与 `parseYMD(str)`（用 `new Date(y, m-1, d)`）。两者同源同口径，转换零偏移。
   **禁止** `toISOString().slice(0,10)` —— 那是 UTC，东八区每天早上会把日期减一天，且**静默**：筛选照跑结果照出，只是边界错了。

2. **初值防御式归一**：17 处现状初值不统一（多数 `''`，`BookingForm` 走 `ymd(TODAY)`，旧渲染器走 `.toString().slice(0,10)`）。组件对 `''` / `null` / `undefined` / `Date` 对象都要正确归一，**不因初值形态不同而抛错或显示空白**。

3. **🔴 弹层必须 teleport 到 `body` 并给足 z-index**。这不是优化项是必需项：原生控件由浏览器渲染、不受页面 `overflow`/`transform` 影响；自绘浮层会被裁。ELN 的筛选面板 / 行操作弹窗 / 资源中心筛选条都有 `overflow` 或 `transform` 上下文，旧渲染器那2 处还嵌在 AG Grid 单元格里（AG Grid 自带高层级弹层）。裁掉一半会让用户觉得「比原生控件还难用」。

4. **不引入 range 模式**：单日期组件，不接受数组值。

5. **配置对齐既有习惯**：周日为一周起点、`auto-apply`（选中即生效、弹层自动关闭）、关闭滚轮翻月、固定 6 行月历、不显示「今天」快捷标记。理由：宿主 `date_time_picker` 已是这套行为，用户在原生页已形成肌肉记忆。

6. **视觉沿用 ELN 自己的 token**，不引入宿主 SciNote 外观。既有 `.field-input` / `.rc-date` / `.bf-bare` 三种样式都要能用 `size` 对齐。

7. **不新增 npm 依赖**：`@vuepic/vue-datepicker@^7.4.1` 已在 `package.json`，本 ticket 只是第一次 import 它。构建时间与镜像体积不增加。

## 验收

- 组件能被 ELN 组件用 `import DateField from '.../DateField.vue'` 引入并注册进自己的 `components:{}`（ELN 组件是各自 `import AppIcon` 的显式注册风格，不是全局注册）
- 一个最小用法：`v-model` 绑字符串，点日历选日期后 `v-model` 得到 `'2026-10-11'`，清空后得到 `''`
- `weekdayOf()` 这类依赖字符串的消费方不受影响（组件不改变值的形状）
- `node_modules/@vuepic/vue-datepicker` 已在，无需 install

## 备注

- 这是本 effort 的**承重件**：01~04 全部依赖它。契约一旦定错（比如改成吐 `Date` 对象），后面 4 个 ticket 全要返工。
- 判据是「17 处调用方能不能一行不改」，不是「组件本身功能全不全」。