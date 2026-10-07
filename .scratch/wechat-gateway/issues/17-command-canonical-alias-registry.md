# 17 — 无别名政策 + `/help` 按指令层分组

**What to build:** 落实并锁住「**一个操作只有一个名字**」：已存在的别名全部清除，未来不得再引入；`/help` 按术语表的指令层重写，替代现在的 20 行平铺。

**Why:** 原方案是「登记 canonical + alias」，2026-09-24 **决策反转**为**无别名**。理由：别名倾向于隐性繁殖——`/list` 与 `/listexp`、`/useproject` 与 `/setproject` 之外，还挖出一个**完全没进文档的隐式形状** `/project <ID>`（由路由正则 `\/(?:set|use)?project\s+\d+` 顺手放行）。登记无法阻止这种形状，因为它写在正则里而不是清单里。取消别名后，每个操作的入口唯一，路由也少一层歧义。

**ADR:** 无（加删别名成本极低，不满足 ADR 三条件）｜**术语表:** `addons/wechat_gateway/CONTEXT.md` §5「规范名 / 无别名」

**Blocked by:** None

**Status:** ready-for-agent（别名清除已完成，`/help` 分层待办）

### 已完成（2026-09-24）

- [x] 删除常量 `LIST`（`/list`）与 `USEPROJECT`（`/useproject`）
- [x] 删除 `route_command` 中的通用前缀分支 `text.start_with?(LIST)`
- [x] 收紧正则：`\A\/(?:set|use)?project\s+(\d+)\s*\z` → `%r{\A/setproject\s+(\d+)\s*\z}`，**杀掉 `/project <ID>` 隐式形状**
- [x] `when SETPROJECT, USEPROJECT` → `when SETPROJECT`；用法分支同步去掉 `USEPROJECT`
- [x] HELP_TEXT 删 `/list [n]` 行；`/listexp [n]` 改为自身的说明（不再写「同 /list」）
- [x] 头部指令注释同步
- [x] spec：原「`/useproject` 是别名」用例改为**「已删除的别名不再被识别为指令」**（`/list`、`/useproject 1`、`/project 1` 三者）
- [x] 冒烟回归 **26/26 通过**，含 5 条别名删除断言

### 待办

- [ ] `/help` 按 L0 通道层 / L1 作用域 / L2 创建 / L3 会话草稿 / L4 查询 / L5 特权 **分组**，每组一行标题
  - 每组内部按 `<动词><实体>` 排序（`new` → `set` → `get` → `list`），名称以 `docs/指令参考.md` §三 的四动词表为准
- [ ] 每项说明带**落点实体**（会写到哪里），而不只描述动作
- [ ] `#<ID>` 与 `/setexp` 相邻但明确区分（配合 ticket 16）
- [ ] 新增守卫测试：穷举已废弃写法（`/list`、`/useproject`、`/project <ID>`、`/use`、`/new`、`/project`、`/exp`），断言**不被识别为指令**且按隐式录入处理
- [ ] 术语表 §5 与 `docs/指令参考.md` 保持同步，漂移即为缺陷

**验收：** `/help` 输出含全部六个层标题；守卫测试在有人重新引入别名时变红。

## Answer

## Comments
- 政策变更点：上一轮盘问 Q3 选的是「登记 canonical + alias」，随后用户决定改为**无别名**。术语表相应从「已登记别名清单」改写为「规范名 / 无别名」两条。
- 破坏性变更：`/list …` 与 `/useproject …` 现在按**普通文本**录入处理（内容不丢，但不会再执行原指令）。已同步 docs 与 README。
- 2026-09-24 后续：命名从「写=set / 读=裸实体」升级为**`<动词><实体>` 四动词**（`new` / `set` / `get` / `list`），故查看类再改名 `/project`→`/getproject`、`/exp`→`/getexp`（均在本次一并完成，含代码/spec/文档/术语表）。本 ticket 的 `/help` 分组待办需按新名字执行。
