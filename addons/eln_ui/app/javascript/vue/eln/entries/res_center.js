// ============================================================
// 资源中心页 —— 可嵌入条目（供 SciNote eln_ui addon 挂载）
//
// 关系：
//   main.js              整套 SPA（原型独立跑）
//   project_list.js      项目列表     ← 第 1 页
//   project_detail.js    项目详情     ← 第 2 页
//   exp_detail.js        实验详情     ← 第 3 页
//   task_detail.js       任务详情     ← 第 4 页
//   res_center.js        资源中心     ← 第 5 页（本文件）
//   apply_detail.js      申请详情     ← 第 6 页
// 6 页共用同一批 Vue 组件与 styles/tokens.css，**各自独立打包**。
//
// 数据口径（与既有页同一条规矩：**不编造**）：
//   1. inventory    ← 宿主原生 Inventories 列表组件（repositories/table.vue）所需的
//                      URL / 状态；台账页签直接渲染该组件，不再另起第二个 Vue app
//   2. ledger       ← 原生 RepositoryLedgerRecord 真值（出入库记录，单列页签）
//   3. consume      ← 原生 RepositoryLedgerRecord（reference_type=MyModuleRepositoryRow）
//   4. apply        ← addon 自有 eln_ui_resource_applications（无原生对应）
//   5. cost         ← addon 自有 eln_ui_project_cost_items + 派生聚合
// 真机无对应数据源 → 空数组（页面渲染空态），**绝不回落演示文案**。
// ============================================================

import { createApp, h } from 'vue/dist/vue.esm-bundler.js'
import { PerfectScrollbar } from 'vue3-perfect-scrollbar'
import '../styles/tokens.css'
import { resCenterPayload } from '../data/mock'
import { ui } from '../store/ui'
import ResCenter from '../views/ResCenter.vue'
import { HostRouterLink } from './modifiers/router_link_host'

const injected = window.__ELN_RES_CENTER__ || {}

// 覆盖 payload 子对象（深合并浅一层；nested array 整体替换）
if (injected.inventory) resCenterPayload.inventory = { ...resCenterPayload.inventory, ...injected.inventory }
if (injected.ledger)  resCenterPayload.ledger  = { ...resCenterPayload.ledger,  ...injected.ledger }
if (injected.consume) resCenterPayload.consume = { ...resCenterPayload.consume, ...injected.consume }
if (injected.apply)   resCenterPayload.apply   = { ...resCenterPayload.apply,   ...injected.apply }
if (injected.cost)    resCenterPayload.cost    = { ...resCenterPayload.cost,    ...injected.cost }

// 元数据（页头副标题、Tab 选中态）
if (injected.meta) resCenterPayload.meta = { ...resCenterPayload.meta, ...injected.meta }
if (injected.defaultTab) resCenterPayload.defaultTab = injected.defaultTab

// ui 副本仅给调试用，组件**不**从 ui 读 resCenter
if (injected.meta && injected.meta.team) ui.resCenterTeam = injected.meta.team

const app = createApp({ render: () => h(ResCenter) })

// 宿主共享组件（shared/datatable/table.vue 及其 SelectDropdown / Pagination）
// 在模板与 computed 里直接使用 `this.i18n.t(...)`（与 /projects 同一套栈），
// 而该全局属性由**每个页面的 createApp 各自注入**（见 app/javascript/packs/vue/*.js
// 与 addons/eln_ui/.../packs/eln_project_list.js 的 `app.config.globalProperties.i18n = window.I18n`）。
// 漏注入 → 宿主表渲染期 `i18n` 未定义 → 整张网格空白（表头都不出）。
// window.I18n 由 layout 的 i18n_bundle 在 <head> 注入；兜底仅防该资源缺失时不至于整页崩。
app.config.globalProperties.i18n = window.I18n || { t: (key) => key }

// 资源台账页签直接渲染宿主原生 repositories/table.vue（RepositoriesTable）。
// 该组件树的「授权」弹窗里用了 <perfect-scrollbar>（shared/access_modal/edit.vue、
// assign_flyout.vue 模板里是 kebab 标签，**组件本身没有 import**），而原生 pack
// `packs/vue/repositories_table.js` 正是靠 `app.component('PerfectScrollbar', ...)`
// 提供它 —— 换承载后这个全局注册也得跟着搬过来，否则打开授权弹窗即报未知组件。
app.component('PerfectScrollbar', PerfectScrollbar)

app.component('router-link', HostRouterLink)
app.mount('#eln-res-center')
