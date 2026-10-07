# 11 — 写入层建立可见性闸门：禁掉一切凭 ID 直取宿主实体

**What to build:** 在 `scinote_service_writer` 内把**所有**裸 `Experiment.find(id)` / `Project.find(id)` / 直挂关系替换成「对该用户可见」的取用原语，使 ADR 0025 成为写入层的默认行为，而不是每条指令各自记得去校验。

**Why:** 现已核实：任一已绑定用户凭一个实验 ID，就能向**任意 Team 的任意实验**追加正文、调用 `complete!` 写 `done_at`、列任务。宿主 `TimeTrackable#complete!` 是裸 `update!`，本身不带权限，指望不上。这是本 addon 目前**最严重的缺陷**——它是安全问题，不是体验问题。

**ADR:** 0025（指令权限校验）｜**术语表:** `addons/wechat_gateway/CONTEXT.md`「可见性校验」

**Blocked by:** None — 可以立刻开始，且它是 12、13 的前提。

**Status:** ready-for-agent

- [ ] 新增统一的实体取用原语（实验 / 项目 / 任务三处），内部走宿主可读范围限定到 `@user` 与 `@user.teams`
- [ ] 替换 `get_experiment` / `get_project` 的裸查
- [ ] 替换 `append_note`、`timestamp`、`complete_experiment`、`persist_formulation` 的实验对象来源
- [ ] 替换 `list_mymodules`（先验证所属实验可见，再按其任务取）与 `create_mymodule` 的实验对象来源
- [ ] `assign_user` 已有 `can_manage_experiment_users?`，补上可见性前置
- [ ] 不可见时的错误文案**不区分「不存在」与「不可见」**（同一个 `⚠️ 实验 #N 不存在或无权访问`），避免 ID 存在性变成探测通道
- [ ] `project_available?` 保持现有语义（存在 + 未归档 + 创建实验权限），但内部对象也走同一原语
- [ ] `/admin` 是**唯一例外**：已有 `InstanceAdmin.admin?` 守卫且只读，明确标注它为刻意越界，不被本闸门改写

**验收：** 构造「其他 Team 的实验 ID」与「本 Team 但无权访问的实验 ID」两组用例，断言 `/setexp`、`/listtask`、`/done`、隐式录入全部返回友好提示且**宿主数据未被改动**。

## Answer

## Comments
