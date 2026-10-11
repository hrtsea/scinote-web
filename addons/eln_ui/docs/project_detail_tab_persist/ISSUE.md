# ISSUE-PD-TAB-RESET：项目详情页保存后页签重置到「项目基础信息」

- **类型**：Bug / 体验回归
- **严重度**：中（数据已保存成功，但用户被甩回错误页签，需手动再点回，打断连续操作）
- **引入版本**：2026-10-11 项目详情页 Vue3 重建 + 指标 CRUD 接线
- **状态**：已调研，附 `SPEC.md` / `PRD.md`，代码已修复

## 复现步骤
1. 进入项目详情页 `/projects/:id/eln_project_detail`
2. 点击子页签「项目指标」
3. 点击「添加指标」（或某行的「编辑」），填写并点「保存」
4. 保存成功后页面整页刷新

## 期望
保存后停留在「项目指标」页签，用户可直接看到刚保存的指标行。

## 实际
整页刷新后默认落回「项目基础信息」页签（子页签列表第一项），需手动再点「项目指标」才能看到结果。

## 根因（以代码为真源）
`ProjectDetail.vue` 中所有写操作成功后统一调用 `window.location.reload()` 做刷新：
- `submitMetric()`    → `ProjectDetail.vue:875`
- `submitEdit()`      → `ProjectDetail.vue:770`
- `onTaskBookPicked`  → `ProjectDetail.vue:821`
- `removeMetric()`    → `ProjectDetail.vue:896`
- `toggleMetric()`    → `ProjectDetail.vue:910`

页签状态是组件本地 ref：`const activeSub = ref('basic')`（`ProjectDetail.vue:476`）。

嵌入态（挂进 SciNote）**不装 vue-router**（`router/index.js` 注释明确：每个 entry 只挂一个 view，页面跳转由 Rails 接管），
reload 会令整页重渲染、Vue 应用重挂载，`activeSub` 重新初始化为 `'basic'` —— 故恒落回第一个子页签。

## 影响范围
所有「在详情页执行写操作 → reload」的入口都受影响，不只指标：编辑项目信息、上传任务书、删除/切换指标
刷新后都会落回「项目基础信息」。用户感知最强烈的是指标（表单从非默认页签发起）。

## 修复方案（概述，详见 SPEC.md）
把当前页签态（`activeNav` / `activeSub` / `costScope`）写入 URL query
（`?pd_nav` / `?pd_sub` / `?pd_scope`，用 `history.replaceState` 写，不新增历史记录）；
组件 `onMounted` 时从 `location.search` 读回还原。reload 后用户落回原页签。
零后端改动、零路由改动，纯前端 URL 态持久化（比 `sessionStorage` 更常规、可分享）。

## 验收标准（勾选 = 有据可查的实测结果，非预先勾选）
- [x] 在「项目指标」页签保存指标后，刷新仍停留在「项目指标」且新行可见
      → **E2E V1 实测通过**（2026-10-11 生产容器，项目 326，URL 带 `pd_sub=kpi`）
- [x] 在「项目指标」页签切换达标后，刷新仍停留在「项目指标」
      → **E2E V4 实测通过**（2026-10-11，同上）
- [x] 刷新后页面引用的是新构建产物（修复真生效，非仅缓存命中）
      → **digest 硬证据**：`eln_project_detail-5875de9f…` → `eln_project_detail-41897414…`
- [ ] 在「项目文档」页签上传任务书后，刷新仍停留在「项目文档」
      → 未自动化覆盖（需文件输入），待人工验证
- [ ] 在「项目基础信息」页签编辑保存后，刷新停留在「项目基础信息」
      → 未自动化覆盖，与 V1 同机制（同一 `writeTabToUrl`），待人工验证
- [ ] SPA 模式（`npm run dev`）下页签态同样被记住（跨路由返回不丢）
      → 未验证（该模式用 `createWebHashHistory`，query 写在 hash 前，理论不冲突但未实测）
- [x] 损坏/非法的 URL 参数静默回落默认页签，不阻断页面
      → 代码层白名单校验 + try/catch 实现，E2E 未专项覆盖，待人工验证

> 跑 E2E 前必读：`PROJECT_ID` 必须选签号账号**可编辑**的项目，否则「添加指标」等写入口被
> `canEditBasic` 门控隐藏、场景必 FAIL（页面仍能挂载，易误判为修复失效）。项目 34 的 Owner 是
> `hrtsea@qq.com`，`hpxing@localhost` 无成员关系，仅适合作对照；hpxing 可编辑 326/327/328/329 等。
