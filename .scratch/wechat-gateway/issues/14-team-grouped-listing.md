# 14 — 列表按 Team 分组呈现

**What to build:** 项目 / 实验 / 任务的列表回复，按 Team 分组展示，并把 Team 名带进呈现。

**Why:** 用户隔着 flicker——项目候选是**跨用户所属全部 Team** 收集的，但不带归属标注，多 Team 用户看到的是一串无法分辨来源的编号。Team 是宿主的多租户根，把它在 UI 上抹掉等于丢掉了上下文里最重要的一维。

**ADR:** 0026（Team 作用域）｜**决策要点:** 呈现层解决问题，**不引入 `/setteam`、不新增 team 状态**

**Blocked by:** None

**Status:** ready-for-agent

- [ ] `/listproject`（含 `all`）按 Team 分组，组头显示 Team 名
- [ ] `/list` `/listexp` `/search` 按 Team 分组（同 Team 的项目 / 实验归在一组）
- [ ] `/newexp` 的「选个项目」候选列表同样分组——这条最重要，用户在这里挑的是**长期落点**
- [ ] `/listtask` 归属单一实验，不需分组，但在标题里带上所属 Team
- [ ] 分组不新增任何用户状态、不加任何指令、不改变候选收集范围（**只改呈现**）
- [ ] 更新 `docs/指令参考.md` 的示例输出

**验收：** 构造「同一用户跨两个 Team」的桩数据，断言列表输出含两组组头，且每个编号都能被归属到唯一 Team。

## Answer

## Comments
