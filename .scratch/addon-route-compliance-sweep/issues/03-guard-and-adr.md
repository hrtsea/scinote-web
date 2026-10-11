# 03: 全仓库零残留守卫 + 记录 ADR

**What to build:** 把"宿主 `config/routes.rb` 对所有 addon 零残留"变成一条会失败的常驻测试——将来新增 addon 时若又把路由挂进宿主文件，立刻变红。同时把这次扫尾的结论写进 ADR，让 10 个 addon 的合规状态有据可查。

**Blocked by:** 01 — 迁移 workbench 路由到引擎自注册；02 — 清理 access_control 宿主死路由

**Status:** resolved

- [x] 新增守卫断言：宿主 `config/routes.rb` 不含任何 `to: 'scinote/<addon>/` 形式的 addon 路由（**对全部 addon 统一断言**，不只查本次两个）
- [x] 该守卫对当前 8 个已合规 addon 恒为绿（证明断言没有过度收紧、也没漏检）
- [x] 注入一违反规路由后该守卫精确变红，随后还原（**护栏必须自证有效**，否则等于没装）
- [x] 守卫接入常跑入口（eln_ui 的 test/run.rb 或其等价入口），不会只手工跑一次
- [x] ADR-0022 补记：全部在役 addon 已完成引擎自注册，宿主 routes.rb 零残留
- [x] ADR 中记录 access_control 那条过时注释的处置（mount 早已完成，注释与现实相反）
- [x] 工作区确认无残留改动（`git status` 干净，仅剩 submodule dirty 标记）

## 补充说明

- 守卫的断言对象是**宿主文件内容**（静态可判），不是运行时路由表——因为 `RAILS_ENV=test` 与独立
  runner 进程里 addon 的 `Engine.routes` 都是 0 条，运行时断言在测试环境恒假。
- 正则要覆盖带前导斜杠（`to: '/scinote/...'`）与不带前导斜杠两种写法。access_control 那 4 条死代码
  正是带前导斜杠的，只查一种会漏检。
- "静态护栏必须自证有效"是本项目纪律：注入违规 → 必须精确变红 → 再还原。不做自证的护栏等于纸面护栏。
## 实施记录

- 守卫落在 `addons/eln_ui/test/host_routes_addon_purity_test.rb`（随 eln_ui 的 run.rb 常跑），
  3 个用例：零残留断言 / 检测器自证 / addon 清单非空。
- 🔴 **自证过程本身抓到守卫的真缺陷**：初版正则只认单引号 `to: 'scinote/...'`，
  而我注入的违规样本是**双引号** ⇒ 注入后守卫仍全绿（**假绿**）。
  已改为引号字符类 `['"]`，并把三种写法都纳入自证样本。
- 🔴 **带前导斜杠那一路无法用于自证**：它会让 Rails 加载 routes.rb 时就抛 ArgumentError，
  测试进程起不来 ⇒ 无法验证检测器。已从可运行自证样本中移除，但**保留其识别断言**
  （access_control 死代码正是这个形态，不能漏检）。该结论已写入守卫文件头注释。
- 最终自证结果：正常态 `3 runs / 0 failures` → 注入违规 → `1 failures` 且报出"残留 1 处"
  → 还原 → 回绿。
- 全量测试 333 runs / 1F / 7E / 2 skips —— 与基线（330/1F/7E/2skips）**同一批 8 个失败同名**，
  runs +3 即新增守卫，零引入回归。
- 新增 ADR-0044 记录落地结果与两条实测约束；ADR-0022 补「落地状态」段并指向0044
  （遵守 `docs/agents/domain.md`：不静默覆盖，用显式关联）。
