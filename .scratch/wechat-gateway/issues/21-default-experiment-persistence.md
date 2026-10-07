# 21 — 默认实验持久化 + 「当前实验」解析入口统一（含 `/cancel` 语义加严）

**What to build:** 状态表新增 `default_experiment_id`；把「当前实验」收敛成**一个概念、两种寿命**：`SessionDraftStore` 是长期值的缓存。统一解析入口负责对齐——先读内存索引，落空则从 DB 恢复并写回。**`/cancel` 与失效清理必须同时清两处。**

**Why:** 2026-09-24 盘问 Q4 选中「**像项目一样长期记住**」（偏离了「仅用短期索引」的原推荐）：短期态在多 worker / 进程重启时会丢，用户隔一会儿回到微信发现又得重选一遍目标。

但直接加一列会造出「当前实验」的两个可以各说各话的真值来源——术语表 §10 已经为「当前草稿 vs 当前项目」这类混用立过禁令，实验层面不能重蹈覆辙。以下四条是 Q4=B 的**派生决定**，成本都很低，可随时逆转：

- **D1** 短期索引 = 长期值的缓存，否则会出现「内存说 #12、DB 说 #30」之类的分裂。唯一入口 `resolve_current_experiment`。
- **D2** 恢复前必须重做可见性 + 未归档 + 对应写权限校验（ADR 0025）；失效即清空并提示。实验比项目更容易过期（会收尾 / 归档 / 撤权），拿过期 ID 直接恢复等于替用户选了一个他早已离开的位置。
- **D3** `/cancel` 同时清短期索引与长期默认实验 —— 否则「取消」会被下一条消息立刻撤销，用户被困在同一个实验里。
- **D4** `/setexp <实验ID>` 在既定行为之外（切草稿 + 设默认项目）**同步设为默认实验**，否则 `/setexp` 的效果在重启后只剩一半。

**ADR:** 0028 §5 ｜ **术语表:** `addons/wechat_gateway/CONTEXT.md` §6「默认实验」、§7、§10

**Blocked by:** 11（恢复时的可见性校验依赖基座）、19（状态层泛化）

**Status:** ready-for-agent（除 11 提供的校验接口外无阻塞）

### 待办

- [ ] **迁移决策点**：`20260924120000` **尚未在任何环境执行** → 直接把 `default_experiment_id`（bigint + index）并入该迁移；否则新增 `20260924xxxx_add_default_experiment_id_to_wechat_gateway_user_states.rb`
- [ ] `UserState`：`default_experiment_id` 读写 + 清空接口；同步 `db/structure.sql`
- [ ] `ScinoteServiceWriter#experiment_available?(id, for: :append | :task | :complete)` —— 与既有 `project_available?` 对称，内部委托 ticket 13 的权限矩阵
- [ ] intake：把所有直接读 `@store.get(user_id)` 的分支改为统一解析入口
- [ ] 恢复时回复加提示行：`↩️ 已恢复到上次实验 #N「X」，发 /cancel 可退出`
- [ ] `/cancel`：清两处，文案说明「默认实验已清除，实验本身仍在 SciNote」（ADR 0027 措辞）
- [ ] 默认实验失效（归档 / 撤权 / 已收尾）→ 清空 + 提示，**不静默回落到别处**

**验收:** 进程重启后第一条普通文本仍落到上次的实验，且回复里有恢复提示；`/cancel` 之后不会被下一条消息自动恢复；归档掉该实验后，恢复路径走提示分支而不是静默写入。

## Answer

## Comments

- 别把「恢复」做成无条件信任：`default_experiment_id` 与 `default_project_id` 一样是**用户选择的事实**，不是权限证明。
- 本 ticket 是 ADR 0028 §5 的全部落地；做完之后 ticket 20 才有地方写默认实验。
- 术语表 §10「混用当前草稿与当前项目」一条需同步改写为三者（默认项目 / 默认实验 / 当前草稿缓存）的区分说明。
