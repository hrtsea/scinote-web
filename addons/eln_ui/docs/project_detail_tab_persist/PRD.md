# PRD：项目详情页签态保持（PD-TAB-PERSIST）

## 1. 问题陈述
项目详情页（`eln_project_detail`）在 2026-10-11 完成 Vue3 重建并接入指标 CRUD 后，
用户在任何子页签（项目指标 / 项目文档 / 项目成员 …）执行保存类操作后，页面整页刷新，
总是回落到默认的第一个子页签「项目基础信息」。用户原话：“填写完项目指标保存后，跳转到项目基础信息了，
而不是保存在项目指标页签”。保存本身成功，但操作上下文丢失，需多一次手动点击，打断连续操作。

## 2. 用户故事
作为项目成员，我在项目详情页的「项目指标」页签新增/编辑一条指标并保存后，
希望保存完成后**仍然停留在「项目指标」页签**，并能立即看到刚保存的指标，
这样我可以连续录入多条指标而无需每次都重新点回页签。

## 3. 目标
- **G1**：保存 / 删除 / 切换等写操作后，刷新后停留在操作前所在的子页签。
- **G2**：同时记住父级页签（项目概况 / 实验列表）与花费页签内的 scope 切换，保持一致。
- **G3**：对既有写入口（指标 CRUD、编辑项目信息、上传任务书）统一生效，不逐个打补丁。

## 4. 非目标（Out of scope）
- 不改变「整页 reload 刷新」机制（沿用既有的“最诚实的刷新”约定；in-place 消费返回 payload 刷新网格
  属后续增强，本次不做，避免引入网格重拉复杂度与回归）。
- 采用 URL query（`?pd_nav` / `?pd_sub` / `?pd_scope`）持久化页签态，而非 `sessionStorage` / `localStorage`
  （URL 更常规、可分享、零“串台”顾虑）；不引入 vue-router（dev 态已用 `createWebHashHistory`，
  直接写 hash 会冲掉路由，故只动 query）。
- 不新增 / 修改任何后端端点或路由（Rails 忽略未知 query，无需控制器改动）。

## 5. 范围与约束
- 仅前端改动，落点 `addons/eln_ui/app/javascript/vue/eln/views/ProjectDetail.vue`。
- 嵌入态无 vue-router：用 `history.replaceState` 写 URL query 跨 reload 保持状态（Rails 忽略未知 query、
  Turbo 对 `replaceState` 无反应）；dev 态用 `createWebHashHistory`，query 写在 hash 之前、改 `search` 不触发
  `popstate`，vue-router 无感 —— 两态统一一套代码。
- 必须与既有 SPA 模式（`npm run dev`，装了 vue-router）兼容：见上，query 方案在 dev 态不冲突。

## 6. 验收标准（Acceptance Criteria）
- **AC1**：在「项目指标」页签保存一条指标 → 刷新后仍为「项目指标」且新行出现在网格中。
- **AC2**：在「项目文档」页签上传任务书 → 刷新后仍为「项目文档」。
- **AC3**：编辑项目信息（从页头按钮，可位于任意页签发起）→ 刷新后回到发起时的页签。
- **AC4**：非法 / 损坏存档不崩溃，回落默认页签。
- **AC5**：不引入新的 JS 运行时错误、不引入新的 ≥400 请求。

## 7. 风险与缓解
- **R1 串台**：不同项目共用同一 `sessionStorage` key → 页签态属“用户偏好”，跨项目沿用同一选择可接受；
  且 `sessionStorage` 按浏览器标签页隔离，关闭即清。
- **R2 非法 / 旧 URL 参数**：还原时按白名单校验 `pd_nav` / `pd_sub` / `pd_scope`，非法键静默丢弃；参数即“用户偏好”，可被分享 / 书签，无需版本号。
- **R3 隐私模式 / 容量满**：`setItem` 抛错 → try/catch 静默退化，不影响保存流程。
