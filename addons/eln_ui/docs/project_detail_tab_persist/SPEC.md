# SPEC：项目详情页签态持久化（PD-TAB-PERSIST）

## 1. 变更清单
| 文件 | 改动 | 说明 |
|------|------|------|
| `addons/eln_ui/app/javascript/vue/eln/views/ProjectDetail.vue` | 修改 | 新增页签态 URL query（`?pd_nav/pd_sub/pd_scope`）持久化 + 还原 |
| `F:/elndev/work/shots/e2e_eln_pd_tab_persist.js`（新增） | 新增 | E2E 验收脚本（复用既有 `mksession.rb` + Edge 接缝） |

无后端改动、无路由改动、无新增端点。

## 2. 设计
### 2.1 状态来源
- 既有页签状态（组件本地 ref）：
  - `activeNav`（`'overview' | 'experiments'`，默认 `'overview'`）— `ProjectDetail.vue:465`
  - `activeSub`（`'basic' | 'kpi' | 'docs' | 'member' | 'cost' | 'archive'`，默认 `'basic'`）— `ProjectDetail.vue:476`
  - `costScope`（`'project' | 'user' | 'both'`，默认 `'project'`）— `ProjectDetail.vue:477`
- 页签键全集由 `navItems`（`ProjectDetail.vue:461`）与 `subTabs`（`ProjectDetail.vue:468`）定义，
  持久化还原时以此做白名单校验。

### 2.2 持久化机制
- 载体：URL query，`?pd_nav=<nav>&pd_sub=<sub>&pd_scope=<scope>`（命名空间 `pd_` 避免与宿主 / Rails 参数冲突）。
- 写入：注册 `watch([activeNav, activeSub, costScope], writeTabToUrl)`，页签一变即用
  `history.replaceState(window.history.state, '', url)` 写回（**不**新增历史记录、不触发 Turbo 访问、不触发 vue-router）；
  `costScope` 同步写入，满足 PRD G2。
- 还原：`onMounted(readTabFromUrl)`，组件挂载后从 `location.search` 读回；仅当值在白名单内才赋值，否则忽略（回落默认）。
- 异常：读写均 try/catch，失败静默退化（不阻断保存流程、不阻断页面）。

### 2.3 关键不变量
- 写操作仍走既有 `window.location.reload()`（5 处：`submitMetric` / `submitEdit` / `onTaskBookPicked` /
  `removeMetric` / `toggleMetric`）；本改动**只**补“reload 前后页签态一致”，不改动刷新机制本身。
- 采用 **URL query** 而非 `sessionStorage` / 纯 hash：
  - `sessionStorage` 非惯例、URL 不可分享；
  - 纯 hash 在 dev 态会与 vue-router（`createWebHashHistory`，`router/index.js:178`）抢 `location.hash`、冲掉路由；
  - query 写在 hash 之前，dev 态改 `search` 不触发 `popstate`、vue-router 无感；嵌入态 Rails 忽略未知 query、
    Turbo 对 `replaceState` 无反应 —— 两态统一一套代码。

### 2.4 兼容性
- 嵌入态（挂进 SciNote）：reload = 整页重渲染 → URL query 保留 → 还原成功；链接可分享 / 书签。
- SPA 态（`npm run dev`）：路由切走再切回 → 组件重挂载 → 还原成功；`history.replaceState` 写 `search` 不动
  vue-router 的 hash 路由；首屏无参数时保持默认 `'basic'`。

## 3. 边界条件
1. 首屏无 URL 参数：不读、不写，保持默认页签。
2. URL 参数被手动改成非法值 / 非法键：解析失败或白名单不通过 → 回落默认，不崩溃。
3. 将来页签结构调整：还原时按白名单校验，未知键静默丢弃（参数即偏好，无需版本号）。
4. `history.replaceState` 受限（极少数环境 / 隐私模式）：try/catch 吞掉，功能不降级（只是 URL 不带参数）。

## 4. 验收用例
| # | 用例 | 操作 | 期望 |
|---|------|------|------|
| V1 | 指标保存后留在本页签 | 点「项目指标」→ 添加指标 → 保存 | reload 后 `activeSub === 'kpi'`，新行在网格 |
| V2 | 文档上传后留在本页签 | 点「项目文档」→ 上传任务书 | 刷新后 `activeSub === 'docs'` |
| V3 | 任意页签编辑项目信息 | 在「项目指标」页签点页头「编辑项目信息」→ 保存 | 刷新后回「项目指标」 |
| V4 | 删除 / 切换指标 | 在「项目指标」删 / 切换一行 | 刷新后仍为「项目指标」 |
| V5 | 非法 query | 打开带 `?pd_sub=__bad__` 的详情页 | 页面正常、回落默认页签、无 JS 报错 |
| V6 | SPA 模式 | `npm run dev` 下上述路径 | 行为一致 |
| V7 | 分享链接直达页签 | 打开带 `?pd_sub=kpi` 的详情链接 | 落地即停留在「项目指标」 |

## 5. 回归测试点
- 既有 `eln_ui_project_detail_metric_actions_test.rb`（指标 CRUD 403/200/422）不受影响（纯后端，未改动）。
- 新增 E2E `e2e_eln_pd_tab_persist.js` 覆盖 V1~V4、V7（需容器 + `mksession.rb`，见脚本头注释）。
- 前端无单元测试框架（仓库现状），页签态逻辑为纯函数式且白名单内联，由 E2E 兜底；若后续引入前端测试，
  可抽取 `persistTabState` / `restoreTabState` 为可单测函数。

## 6. 实现备注（已落地并通过真机验收 2026-10-11）
- `ProjectDetail.vue` 变更：`import` 已含 `watch, onMounted`；在 `costScope` 定义后插入持久化块
  （`TAB_PARAMS` / `validSubKeys` / `validNavKeys` / `validScopeKeys` / `readTabFromUrl` / `writeTabToUrl` / `watch` / `onMounted`）。

### 真机验收结果（生产容器 `scinote_web_production`）
- 部署序列：`docker cp` 源码 → 容器内定向 webpack（`ENTRIES=eln_project_detail`，44.5s）→ `assets:precompile`
  → `docker restart`。生效硬证据：详情页 HTML 引用的 digest 由 `eln_project_detail-5875de9f…`
  变为 `eln_project_detail-41897414…`（新 1 次 / 旧 0 次）。
- E2E `e2e_eln_pd_tab_persist.js` 在项目 **326**（`hpxing@localhost` 为 Owner，可编辑）**2/2 通过**：
  - V1 添加指标保存 → reload 后停留「项目指标」，URL `?pd_nav=overview&pd_sub=kpi&pd_scope=project`
  - V4 切换达标 → reload 后停留「项目指标」，URL 带 `pd_sub=kpi`
- ⚠️ 跑 E2E 必读：`PROJECT_ID` 必须选签号账号**可编辑**的项目，否则写入口被 `canEditBasic` 门控隐藏、
  场景必 FAIL（页面仍 `mounted=true`，易误判为修复失效）。项目 34 的 Owner 是 `hrtsea@qq.com`，
  hpxing 无成员关系，仅适合作对照组。详见脚本头注释。
- 未覆盖：V2（文档上传，需文件输入）、V3（跨页签编辑）、V5（非法 query）、V6（`npm run dev` SPA 态）。

## 7. 关联
- `ISSUE-PD-TAB-RESET`（同目录 `ISSUE.md`）
- `PRD-PD-TAB-PERSIST`（同目录 `PRD.md`）
- 代码真源：`addons/eln_ui/app/javascript/vue/eln/views/ProjectDetail.vue`
