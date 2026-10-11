// ============================================================
// 项目详情页 —— 可嵌入条目（供 SciNote eln_ui addon 挂载）
//
// 为什么要单独做一个 entry（而不复用 src/main.js）：
//   main.js 挂的是**整套 SPA**（侧栏 232 + vue-router + 18 条路由）。
//   改造 SciNote 时不能把整套壳子搬进 Rails 页面 —— 宿主有自己的侧栏/面包屑/
//   布局容器（sci--layout），Vue 只该接管**内容区**这一块。
//   所以这里只挂载 <ProjectDetail>，并给它补一个 router-link 替身。
//
// 为什么 router-link 要替身：
//   ProjectDetail 模板里用了 <router-link>（面包屑「项目列表」、实验名链接），
//   但嵌入态**没有 vue-router**（路由由宿主 Rails 负责）。装一个只渲染 <a href>
//   的等价替身，组件源码一行都不用改 —— 保持「原型 = 真机同一份组件」。
//
// 数据源（同一份组件、两种数据）：
//   1. 原型独立跑（npm run dev）：走 src/data/mock 的画布演示值；
//   2. 挂进 SciNote：宿主先把真实 JSON 写到 window.__ELN_PROJECT_DETAIL__，
//      这里把它覆盖到 mock 的导出对象上（ESM 命名空间导出是**对象引用**，
//      Object.assign 改的是同一个对象，ProjectDetail 读到的就是新值）。
//      因此 mock.js 一行都不用改，原型依旧能独立打开。
// ============================================================

import { createApp, h } from 'vue/dist/vue.esm-bundler.js'
import '../styles/tokens.css'
import * as mock from '../data/mock'
import ProjectDetail from '../views/ProjectDetail.vue'
// ⚠ 共用替身（2026-10-04 修）：这里原先是「原样透传 href」的本地副本，
//   导致详情页面包屑「项目列表」的 to="/projects" 没被改写 → 点一下跳回**原生**
//   项目列表，而那正是我们正在改造掉的目标页。列表页 entry 早就改写了，
//   两边各写一份就是漏配的根源，现已归口到 modifiers/router_link_host.js。
import { HostRouterLink } from './modifiers/router_link_host'
import { ui } from '../store/ui'

// ---------- 真机数据注入 ----------
const injected = window.__ELN_PROJECT_DETAIL__ || {}

function patchObject(target, next) {
  if (next && typeof next === 'object') Object.assign(target, next)
}

function replaceList(target, next) {
  if (Array.isArray(next)) target.splice(0, target.length, ...next)
}

patchObject(mock.projectBasic, injected.projectBasic)
replaceList(mock.members, injected.members)
replaceList(mock.experiments, injected.experiments)

// ---------- 项目指标 / 文档 / 花费：嵌入态**必须无条件清空** ----------
// ⚠ 这三组在原型里是画布演示值（指标 3 条、必传文档 5 类 + 其他文档 3 份、
//   花费 ¥86.4万）。SciNote 原生**没有**项目级指标 / 项目文档台账 / 花费模型
//   （花费口径 REQ-RES-CONSUME 还没落地），所以宿主给的一定是空集。
//   这里哪怕 injected 里没带，也要 replaceList 成 []：不 replace 就会留下原型演示值，
//   页面看着「有数据」，其实全是假的 —— 用户报的「下钻数据未接入真实数据」就是这么来的。
//   空集落到组件里会走**空态**（暂不显示 + 说明取不到的原因），而不是拿演示值顶。
replaceList(mock.projectMetrics, injected.projectMetrics || [])
replaceList(mock.requiredDocs, injected.requiredDocs || [])
replaceList(mock.otherDocs, injected.otherDocs || [])
patchObject(mock.projectCost, injected.projectCost || { total: '', note: '', rows: [], splits: [] })
// 报告 §5 第 6 项 #11 / #10：任务关闭审核汇总、项目归档导出态（真机由宿主注入，嵌入态无则空态）
patchObject(mock.taskCloseReview, injected.taskCloseReview || { total: 0, closed: 0, pending: 0, rejected: 0, indicatorDriven: false, tasks: [] })
patchObject(mock.projectArchive, injected.projectArchive || { archived: false, archivedAt: null, canExport: false, exportUrl: '' })
// 页头三键：权限位与动作端点都必须来自宿主。缺了就维持 mock 的全 false / 空串，
// 组件据此不渲染按钮（而不是渲染一个点了没反应的按钮）。
patchObject(mock.permissions, injected.permissions || { canEditBasic: false, canUploadDocs: false, canChangeStatus: false })
patchObject(mock.actions, injected.actions || { updateProject: '', changeStatus: '', uploadTaskBook: '', addMetric: '' })

// ---------- 面包屑下钻地址（宿主注入真实URL；不给就null → 组件回落原型路径）----------
// 铁律：前端不写死宿主路由。这两段以前在模板里写死 /projects，
// 真机上点「项目列表」会跳去原生页（丢掉工具栏 7 控件），点项目名更会 404。
if (injected.listUrl !== undefined) ui.projectListUrl = injected.listUrl

// ---------- 挂载 ----------
const app = createApp({ render: () => h(ProjectDetail) })
app.component('router-link', HostRouterLink)
// 🔴 i18n 全局属性必须挂：页面上 6 张表改用宿主 shared/datatable（AG Grid）栈后，
//   栈内部的分页条 / 条目计数 / 错误提示都读 `this.i18n.t(...)`（这些是 datatable.* 老 key，
//   中文/英文双语都在已提交的 translations.js 里）。
//   漏挂的症状是「表格区域空白 + 控制台 undefined.t」—— 不是显式报错，很难一眼看出。
//   与 teams_table.js 的挂法一致（同一套宿主栈、同一条约束）。
app.config.globalProperties.i18n = window.I18n
app.mount('#eln-project-detail')
