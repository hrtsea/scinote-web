# 19 — 待选（pending）泛化为「单步 · 可串联」：支持 `select_experiment`

**What to build:** `UserStateStore` 的待选从「只能等选项目」泛化为「等任意一个选择步骤」：`pending_action` 取值扩为 `select_project | select_experiment`，payload 按 action 携带各自字段。**两级引导不是一次写两步队列**，而是第一段被消费后**立刻覆盖写入第二个 pending**——同一时刻永远只有一个待选步骤。

**Why:** `/newtask` 的目标容器是「某个项目里的实验」，比 `/newexp` 多一层。保持 `pending_action` 只有一个取值会让第二步无处安放；而做成通用步骤队列，对当前最深两级的实际需求属于过度设计（存储、超时、回滚都要一起付钱）。单步 + 串联是这两端之间的最小解。

**ADR:** 0028 §2 ｜ **术语表:** `addons/wechat_gateway/CONTEXT.md` §6「待选（pending）」

**Blocked by:** None（纯状态层，不触碰宿主查询，可以先于 ticket 11 开工）

**Status:** ready-for-agent

### 待办

- [ ] `UserStateStore#start_pending(user, action:, payload:, ttl:)` 签名放开到任意 action，并白名单校验取值
- [ ] `select_experiment` 的 payload **必须带 `project_id`**；DB 里只存候选 **id 列表**，不存实体快照
- [ ] 保持「同时只有一个 pending」不变：写新 pending = 覆盖旧的
- [ ] `MemoryUserStateStore` 同步实现（同一套接口，供单测与无 DB 场景注入）
- [ ] 单测：两级串联在**只有一份 DB 记录**下如何表达（第二段 = 覆盖写）、TTL 各自独立计时

**验收:** `select_project` 与 `select_experiment` 都能存 / 读 / 过期；断言同一时刻 `pending_action` 只有一个值。

## Answer

## Comments

- 现状：`pending_action` 目前仅 `select_project` 一个取值（迁移 `20260924120000`，**尚未执行**）。本 ticket 是把它变成可扩展的最小改动。
- 依赖倒置：本 ticket 不引入任何宿主模型查询，因此不与权限闸门相互阻塞；真正的候选过滤在 ticket 20。
