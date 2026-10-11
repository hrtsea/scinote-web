# 01: 建立路由基线与引擎自注册骨架

**What to build:** 让这次迁移从第一天起就是**可自证正确**的——在任何路由被搬动之前，先让机器能说出"这 30 条路由的动词、路径、helper 名是什么"，并证明以后能一条不差地比对回来。同时把引擎自注册的两件能力装上（路由自挂载 + 具名 helper 转发），但**一条路由都还不搬**。

本 ticket 不改变任何用户可见行为，它的价值是把"靠人工数 30 条路由确认没改坏"变成"机器断言"。

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] 基线文件已生成，含 ELN UI 全部 30 条路由的「动词 + 路径 + helper 名」三元组，数量断言 = 30
      → `test/fixtures/eln_ui_routes_baseline.json`，`count=30 named=29 anon=1`；11 个 controller 分布与审阅时交叉核对一致。
- [x] 基线可重跑且幂等：同一份代码连续两次跑出完全相同的结果
      → 生成器连跑两次 md5 均为 `b311ba5227e60647e93afbd41a09129a`。
- [x] 基线能区分「新增 / 缺失 / 改名」三类偏差，而不是只比对总数（总数相等但换了名字必须判失败）
      → 比对键为三元组；缺��与新增分别列出，疑似改名逐条对齐路径报出差异行。
- [x] engine 已具备路由自注册能力：initializer 显式声明 `after: :add_routes`，以 append 方式挂载到根路径
      → 实测 `Scinote::ElnUi::Engine.routes` 已就位（骨架阶段路由数为 0，符合"一条都还没搬"）。
- [x] engine 已具备具名 helper 转发能力：对宿主 url_helpers 用 `define_method` 逐个转发一层；**禁止**用 `include` 并入引擎 url_helpers 模块
      → 转发清单**从基线读**（手抄实测立刻错 5 个：`eln_notification_read` / `eln_project_approver` 等）；读不到基线时**大声 raise**，不静默退化为"不转发"。
- [x] 此时宿主 `config/routes.rb` 仍含全部 30 条 ELN UI 路由（骨架不得改变现状）
      → 实测 `ELN_ROUTE_COUNT=30`，`HOST_ROUTES` 断言在 `MIGRATED=false` 下钉住 30 条。
- [x] ELN UI 全部 11 个页面仍然可达（骨架无回归）
      → 签名会话逐个 curl：**12/12 全部 HTTP 200**（含孤儿 V1 与两个网格端点）；既有 E2E 亦 2/2 通过。
- [x] 转发机制的正确性已被探针验证过至少一条
      → 引擎侧 helper 就位后自动转发；骨架阶段 `respond_to?` 守卫实测正确跳过（`ENGINE_SIDE_PRESENT=0`），
        `HOST_STILL_WORKS=/projects/34/eln_project_detail` 证明宿主原生helper 未被破坏。

## 实施记录（供 ticket 02 参考）

### 🔴 本轮实测纠正了两个设计错误（都差点埋雷）
1. **骨架阶段不能强行转发 helper**：引擎侧尚无路由时转发体会 `NoMethodError`；更隐蔽的是
   **宿主会用自己的同名 helper 覆盖掉转发**（宿主路由表已有这些名字，定义在后优先级更高），
   实测 helper 的 `owner` 仍是宿主的 `::ROUTES` —— 看起来"装好了"其实完全没生效。
   正解=加 `engine_helpers.respond_to?` 守卫：01 阶段明确跳过（此时宿主原生 helper 就是权威），
   02 迁完路由后自动生效。幂等、可重复执行。
   （access_control 是**路由已迁入引擎后**才装转发，两者配套；不能照抄其顺序。）
2. **`module_eval` 里取不到 `class Engine` 上的常量**：词法作用域看不见 `HOST_ROUTE_HELPERS`，
   会抛 NameError；若被 rescue 掉就静默变成"一个都没转发"。正解=块外取值再传参。

### 对照实验（证明零回归，未隔离的因果不许当结论）
全量测试改动前 `325 runs, 1 failures, 7 errors`，改动后 `330 runs, 1 failures, 7 errors` ——
**同一批 8 个失败、同样的测试名**（ProjectList 6 + ResCenter 1 + Metric 1，均与路由无关，
属既有债）。runs 增加 5 即本次新增的基线用例。⇒ 本改动**零引入回归**。

### 踩坑
- 容器内 addon 目录属 root，`rails runner` 建 `test/fixtures/` 报 `Errno::EACCES` ⇒ 须 `docker exec -u root`。
- `docker cp` 到不存在的宿主目录会报 `invalid output path` ⇒ 先 `mkdir`。
- `MOUNTED_ENGINES` 这类"按 `r.app` 类名过滤"的探测**不可靠**（它不是判定引擎是否挂载的可靠信号，
  会给出"没挂载"的假象）；可靠的判据是 `Engine.routes` 是否就位 + `rails routes` 的 mount 条目。

### 遗留（属 ticket 02）
- `MIGRATED` 开关目前为 `false`；02 迁完路由后须置为 `true`，该断言即从"钉住现状"变成"强制清零"。
- 29 个具名 helper 的转发在 02 之前处于"未安装"状态（守卫跳过），这是**预期**的，非缺陷。

## 补充说明

- 本 ticket 只做"装能力 + 建基线"，**不动任何路由定义**。若发现宿主文件里 ELN UI 路由块与其他 addon 交错，先停下报告，不要就地拆分。
- 基线的生成方式应是一次性脚本产物而非手工誊抄——手抄 30 条三元组本身就是新的错误来源。
- 写实现时注意引擎已声明 `isolate_namespace`，其 route set 自带控制器命名空间前缀；本 ticket 只装能力不写路由，前缀问题留到 02 处理。