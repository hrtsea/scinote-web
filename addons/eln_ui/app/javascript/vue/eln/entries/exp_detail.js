// ============================================================
// 实验详情页 —— 可嵌入条目（供 SciNote eln_ui addon 挂载）
//
// 与已有两个 entry 的关系：
//   main.js       挂整套 SPA（原型独立跑用，不进 SciNote）
//   project_list.js 挂项目列表页   ← 第三页
//   project_detail.js 挂项目详情页 ← 第四页
//   exp_detail.js   挂实验详情页   ← 第五页（本文件）
//   四页共用同一批 Vue 组件与 styles/tokens.css，但**各自独立打包**：
//   宿主页面只引入自己那一页的 bundle，避免为了看一个实验页把
//   项目/资源/报表那一坨都拉下来。
//
// 路由改写（HostRouterLink 独家负责，这里不重复写）：
//   实验任务面板里每个任务名是 <router-link :to="`/tasks/${t.id}`">，
//   原型那是个扁平演示路由；真机上 MyModule 挂在实验之下，真实地址是
//   /experiments/:experiment_id/my_modules/:id。HostRouterLink 读本文件
//   上面的 window.__ELN_EXP_DETAIL__.experimentId 拼出原生两级路由。
//
// 数据口径（与列表页/详情页同一条规矩：**不编造**）：
//   1. tasks 是**真** MyModule（名称 / 状态流 / 负责人 / 截止）；
//   2. expDesignVars 原生根本没有 DOE 设计变量表 → 保持空数组，
//      「实验设计与配方优化」面板就渲染成空表 + 原型那几个计算按钮，
//      不强塞一个假数值进去（DEC-009 的实验级 DO{E} 属纯二开）。
//   3. 原型的 5 档状态（pending/active/submitted/pendingReview/closed）在原生
//      只有 3 档（Not started / In progress / Completed），
//      这里**落到原型取值域内**：Not started→pending、In progress→active、
//      Completed→closed。原生没有的 submitted / pendingReview 两档自然不出现，
//      而不是给它们编一个假状态。taskStatusLabel 一个字都不用改。
// ============================================================

import { createApp, h } from 'vue/dist/vue.esm-bundler.js'
import '../styles/tokens.css'
import * as mock from '../data/mock'
import { ui } from '../store/ui'
import ExperimentDetail from '../views/ExperimentDetail.vue'
import { HostRouterLink } from './modifiers/router_link_host'

// ---------- 真机数据注入 ----------
// 宿主先把真实 JSON 写在 window.__ELN_EXP_DETAIL__ 上；没有就是原型演示态。
const injected = window.__ELN_EXP_DETAIL__ || {}

function replaceList(target, next) {
  if (Array.isArray(next)) target.splice(0, target.length, ...next)
}

// tasks：真 MyModule 列表（含 owner / due / status）
replaceList(mock.tasks, injected.tasks)

// expDesignVars：原生无 DOE 变量表 → 空数组（显式留白，不编造设计变量）
replaceList(mock.expDesignVars, injected.expDesignVars)

// expNav / expSubTabs：宿主按权限裁剪后给出（DEC-001 组员不可见「实验设计」入口）
replaceList(mock.expNav, injected.expNav)
replaceList(mock.expSubTabs, injected.expSubTabs)

// experimentId 只有 HostRouterLink 要用（拼原生两级任务路由 /experiments/:exp_id/my_modules/:id）。
// ⚠ 不能照抄列表页的 ui.canCreateProject 套路往 store/ui 里塞：ExperimentDetail.vue
//   根本没读 ui（只有 ProjectList.vue 的按钮是 v-if="ui.canCreateProject"），
//   塞进去就是**假生效** —— 看着像按权限显隐了，其实组件压根不认。
//   所以这里只同步 window 这份（HostRouterLink 的取值来源），别再叠一个 ui 副本。
if (injected.experimentId !== undefined) {
  window.__ELN_EXP_DETAIL__.experimentId = injected.experimentId
  ui.experimentId = injected.experimentId // 仅调试用，组件不读
}

// 默认**左栏**页签：宿主注入 'tasks' → 首屏直接是真任务列表（PRD §7.7「tasks 默认选中」）。
// ⚠ 只注入 expDefaultNav 还不够：任务表格挂在 activeNav==='tasks' 分支上，
//   子页签 activeSub 只管「实验概况」里显示哪个 Pane（首屏若还停在 design，
//   点进「实验概况」就是"页签栏 3 项、底下却是 DOE 面板"，面板根本点不到）。
//   所以 expDefaultSub 由宿主按权限给（有 design 权限才 'design'，否则 'info'）。
// 都不注入时保持原型行为（'overview' + 'design'），原型演示态一行没变。
if (injected.expDefaultNav !== undefined) {
  ui.expDefaultNav = injected.expDefaultNav
}
if (injected.expDefaultSub !== undefined) {
  ui.expDefaultSub = injected.expDefaultSub
}

// 面包屑的「项目名」是原型的**写死假链接** /projects/PR1025240（画布演示值），
// 原样透传会链到一个不存在的项目。宿主给真 projectId，HostRouterLink 用它替换。
if (injected.projectId !== undefined) {
  window.__ELN_EXP_DETAIL__.projectId = injected.projectId
}

// 「实验目的 / 实验方案与方法」两块正文：原生**没有**承载面，真值来自实验档案表
// （eln_ui_experiment_profiles.purpose / method）。没档案时 payload 给空串，
// 组件会自动显示「未填写」的留白说明；注入演示文案只发生在原型独立跑（ui 为空）。
if (injected.expPurpose !== undefined) ui.expPurpose = injected.expPurpose
if (injected.expMethod !== undefined) ui.expMethod = injected.expMethod

// 标题 / 面包屑项目名 / 状态徽标：三处原型演示文案，真机一律换成真值。
// 不注入时组件自动落回原型文案（ui.expTitle 为空 = 原型独立跑的行为）。
if (injected.experimentName !== undefined) ui.expTitle = injected.experimentName
if (injected.projectName !== undefined) ui.expProjectName = injected.projectName
// 面包屑第二级「项目名」的下钻地址（宿主给真项目详情页）；不给就null，
// 组件落回原型路径 —— 绝不顶着演示项目 id PR1025240 在真机上点出404。
if (injected.projectDetailUrl !== undefined) ui.projectDetailUrl = injected.projectDetailUrl
if (injected.statusText !== undefined) ui.expStatusText = injected.statusText

// 「实验信息」面板 7 格：整页最后一块原型硬编码假值（EX1 / 硅胶配方… / 张负责人 /
// 2026-09-30 / 1/3 任务）。宿主按 payload 给一整个对象，缺哪一格组件就落回哪一格的
// 原型演示值，所以这里**逐格判 undefined**，不能整个覆盖成 undefined。
if (injected.expInfo) {
  const info = injected.expInfo
  if (info.code !== undefined) ui.expInfo = { ...(ui.expInfo || {}), code: info.code }
  if (info.name !== undefined) ui.expInfo = { ...(ui.expInfo || {}), name: info.name }
  if (info.state !== undefined) ui.expInfo = { ...(ui.expInfo || {}), state: info.state }
  if (info.stateColor !== undefined) ui.expInfo = { ...(ui.expInfo || {}), stateColor: info.stateColor }
  if (info.project !== undefined) ui.expInfo = { ...(ui.expInfo || {}), project: info.project }
  if (info.owner !== undefined) ui.expInfo = { ...(ui.expInfo || {}), owner: info.owner }
  if (info.due !== undefined) ui.expInfo = { ...(ui.expInfo || {}), due: info.due }
  if (info.progress !== undefined) ui.expInfo = { ...(ui.expInfo || {}), progress: info.progress }
}

// ⚠ 权限显隐走的是**上面那条**：expSubTabs 由宿主按权限裁剪（DEC-001 组员不给
//   「实验设计与配方优化」入口）。标题行的「新建任务」按钮在组件里是硬编码常显，
//   真机上要不要显隐，得等规格侧把 SCN-EXP-DETAIL-5 落到按钮上再定（记 OPEN），
//   这里不擅自去改组件模板。

// ---------- 挂载 ----------
createApp({ render: () => h(ExperimentDetail) })
  .component('router-link', HostRouterLink)
  .mount('#eln-exp-detail')
