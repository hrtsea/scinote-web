// ============================================================
// 项目列表页 —— 可嵌入条目（供 SciNote eln_ui addon 挂载）
//
// 为什么要单独做一个 entry（而不复用 src/main.js / project_detail.js）：
//   main.js 挂的是**整套 SPA**（侧栏 232 + vue-router + 18 条路由）；
//   project_detail.js 挂的是单页（项目详情页）。
//   这里挂的是第三页（项目列表页），三者共用同一批 Vue 组件与样式，
//   但各自独立打包 —— 宿主 Rails 页面只引入自己那一页的 bundle，
//   避免为了看一个列表页而把详情/实验/资源的 bundle 全拉下来。
//
// 为什么 router-link 要替身：
//   ProjectList 模板里项目名是 <router-link :to="`/projects/${p.id}`">，
//   嵌入态**没有 vue-router**（路由由宿主 Rails 负责）。装一个只渲染 <a href>
//   的等价替身，组件源码一行都不用改 —— 保持「原型 = 真机同一份组件」。
//   但 href 要在真机上改写：原生 /projects/:id 是 projects#show，会 302 到
//   实验列表（projects_controller.rb:49-57），那是**原生页面**，不是我们要改造的目标。
//   所以这里把「纯数字 id 的 /projects/:id」翻译成宿主的详情路由。
//
// 为什么「新建项目」按钮要按权限显隐：
//   PRD §7.4 SCN-PROJ-LIST-4：新建项目按钮仅单位管理员可见可用。
//   原型的 mock 数据不体现权限，真机由宿主注入 canCreateProject 决定。
//   这里**不改组件**（组件仍无条件渲染按钮），只在挂载前把宿主的判断
//   写进 store/ui 的 ui 对象 —— 组件读的是同一个响应式对象，立刻生效。
//
// 数据源（同一份组件、两种数据）：
//   1. 原型独立跑（npm run dev）：走 src/data/mock 的画布演示值（4 条）；
//   2. 挂进 SciNote：宿主先把真实 JSON 写到 window.__ELN_PROJECT_LIST__，
//      这里把它覆盖到 mock.projects（ESM 命名空间导出是**对象引用**，
//      splice 改的是同一个数组，ProjectList 读到的就是新值）。
//      因此 mock.js 一行都不用改，原型依旧能独立打开。
// ============================================================

import { createApp, h } from 'vue/dist/vue.esm-bundler.js'
import '../styles/tokens.css'
import * as mock from '../data/mock'
import { ui, fetchTableState } from '../store/ui'
import ProjectList from '../views/ProjectList.vue'

// 浮层（筛选面板 / 新建项目 / 新建文件夹 / 行菜单 / 批量条 / 导航抽屉）
// 在原型里是 App.vue 挂的；嵌入态没有 App.vue，所以在这里按同样顺序挂一遍。
// ⚠ 少挂任何一个都会出现「按钮点了没反应」—— 组件开了 ui.xxxOpen，但没人渲染它。
import NavigatorPanel from '../components/overlays/NavigatorPanel.vue'
import NewProjectModal from '../components/overlays/NewProjectModal.vue'
import NewFolderModal from '../components/overlays/NewFolderModal.vue'
import FilterPanel from '../components/overlays/FilterPanel.vue'
import RowMenu from '../components/overlays/RowMenu.vue'
import RowActionModal from '../components/overlays/RowActionModal.vue'
import BulkActionBar from '../components/overlays/BulkActionBar.vue'

// ---------- router-link 替身（真机改写宿主路由） ----------
// 与详情页 entry 共用同一个模块：两页各写一份副本迟早改漏
//   （2026-10-04 实测教训：详情页那份漏了 /projects 的改写，
//     验收才抓到「面包屑跳回原生 /projects」）。
import { HostRouterLink } from './modifiers/router_link_host'

// ---------- 真机数据注入 ----------
const injected = window.__ELN_PROJECT_LIST__ || {}

function replaceList(target, next) {
  if (Array.isArray(next)) target.splice(0, target.length, ...next)
}

replaceList(mock.projects, injected.projects)

// 不注入时保持原型行为（按钮可见）；注入了就以宿主权限为准。
if (injected.canCreateProject !== undefined) ui.canCreateProject = !!injected.canCreateProject

// ---------- 工具栏能力注入 ----------
// 下面这批字段**只有挂进 SciNote 才有值**。留空时 store 里所有的网络动作
// （刷新列表 / 新建项目 / 新建文件夹）都会自动退化成空操作 —— 原型独立跑依旧是纯演示。
if (injected.canCreateFolder !== undefined) ui.canCreateFolder = !!injected.canCreateFolder
if (injected.createUrls) ui.createUrls = injected.createUrls
if (injected.listUrl) ui.listUrl = injected.listUrl
if (injected.viewMode) ui.viewMode = injected.viewMode
if (Array.isArray(injected.folders)) ui.folders = injected.folders
if (Array.isArray(injected.members)) ui.members = injected.members
// 行菜单「访问权限」弹窗 →「添加成员」下拉的可指派成员端点（原生 access_permissions#new）
if (injected.assignableUsersUrl) ui.assignableUsersUrl = injected.assignableUsersUrl
// 列状态持久化端点基址（V1.33）：payload 下发 /user_settings，前端拼 /:key。
// 空 = 原型独立跑，不持久化。
if (injected.userSettingsUrl) ui.userSettingsUrl = injected.userSettingsUrl
// 工作台入口（OPEN-WB-7）：项目列表页头那颗「工作台」的落点由 payload 下发，
// 前端不写死宿主路由（铁律）。空值 = 不渲染按钮。
if (injected.workbenchUrl) ui.workbenchUrl = injected.workbenchUrl
if (Array.isArray(injected.headOfProjects)) ui.headOfProjects = injected.headOfProjects
if (Array.isArray(injected.statuses)) ui.statuses = injected.statuses
if (Array.isArray(injected.defaultRoles)) ui.defaultRoles = injected.defaultRoles
// 筛选项取数失败项（option_failed! 记的 key）。非空 = 对应下拉是真的取不到数据，
// 前端必须显式提示「部分筛选项不可用」，不能让人误以为「就是没数据」。
if (Array.isArray(injected.filterOptionErrors)) ui.filterOptionErrors = injected.filterOptionErrors

// ---------- 深链筛选条件回填（V1.27 闭合 OPEN-WB-DRILL-8）----------
// 服务端把本次请求的 filters 归一化后随 payload 下发（initialFilters），这里回填 ui.filters。
// 不回填有两层后果：
//   ① 打开筛选面板**看不到**已生效条件（深链 ?filters[members][]=35 貌似"没生效"）；
//   ② **更严重**：任何工具栏交互（搜索/切视图/切归档/排序/新建后刷新）都会走
//      refreshList() → buildListQuery()，而它只读 ui.filters —— 空 filters ⇒ 深链条件被
//      **静默丢弃**，列表突然变多、页面没有任何提示。
// ⚠ 类型必须归一（服务端已把 members 里的字符串 "35" 转成数字 35）：FilterPanel 的
//   <option :value="m.id"> 是真机数字 id，v-model 多选按**严格相等**匹配 option，
//   字符串 vs 数字会导致「回填了但多选框不显示」这种最难查的静默失败。
//   归一规则在服务端 ProjectListPayload#normalized_initial_filters，前端只管 assign。
// 注：view_mode 已在上方 `if (injected.viewMode) ui.viewMode = ...` 回填，此处不重复。
if (injected.initialFilters && typeof injected.initialFilters === 'object') {
  Object.assign(ui.filters, injected.initialFilters)
}

// ---------- V1.31 分页状态回填 ----------
// 服务端的分页状态是**唯一真源**：下拉档位、共 N 条、页码控件全读它渲染。
// 同一段逻辑首屏（injected）与每次重拉（listConsumer）都要用，抽成一个函数，
// 避免只改一处（「原型两处各写一份副本迟早改漏」是本 entry 的老教训）。
//
// ⚠ 必须把**前端**的 page / perPage 对齐到服务端归一化后的值：
//   用户手改 URL 传 per_page=999 或 page=abc 时，服务端会归一（回落 20 / 第 1 页），
//   若前端还留着原值，就会出现「下拉写着 999、列表只有 20 条」这种自相矛盾的画面。
//   服务端说了算，前端跟着它走。
function applyPagination(data) {
  if (!data || typeof data !== 'object') return
  ui.pagination = { ...ui.pagination, ...data }
  const p = Number(data.page)
  const pp = Number(data.perPage)
  if (Number.isFinite(p) && p >= 1) ui.page = p
  if (Number.isFinite(pp) && pp >= 0) ui.perPage = pp
}

applyPagination(injected.pagination)

// ---------- V1.32 行集合 / 文件夹层级回填 ----------
// 同一段逻辑首屏（injected）与每次重拉（listConsumer）都要用 —— 抽成一个函数。
//
// ⚠ `ui.folderId` 是**请求参数的一格**，不是展示用的：它必须跟着服务端下发的
//   `folderNav.current` 走。不同步的后果是「用户点了排序/翻页，列表悄悄退回顶层」——
//   服务端 200、前端无异常，只有用户自己发现「我怎么出来了」。
//   服务端把非法/越界的 `project_folder_id` 归一成顶层（current 为 null），
//   前端据此把 folderId 也清空，两边永远一致。
function applyRowSetMeta(data) {
  if (!data || typeof data !== 'object') return
  const nav = data.folderNav && typeof data.folderNav === 'object'
    ? data.folderNav
    : { current: null, trail: [], upUrl: null }
  ui.folderNav = nav
  ui.currentFolder = nav.current || null
  ui.folderId = nav.current && nav.current.id != null ? String(nav.current.id) : ''

  const pc = Number(data.projectCount)
  if (Number.isFinite(pc) && pc >= 0) ui.projectCount = pc
}

applyRowSetMeta(injected)

// 拉回来的数据写回组件读的那同一份数组（ESM 命名空间导出是对象引用，splice 生效）。
ui.listConsumer = (data) => {
  replaceList(mock.projects, data.projects)
  if (data.canCreateProject !== undefined) ui.canCreateProject = !!data.canCreateProject
  if (data.canCreateFolder !== undefined) ui.canCreateFolder = !!data.canCreateFolder
  applyPagination(data.pagination)
  applyRowSetMeta(data)
}

// ---------- 列状态持久化（V1.33）----------
// 挂载前异步拉取按用户存的列显隐 / 钉列状态；不阻塞首屏（解析回来后
// 响应式 ui 直接驱动重渲染）。失败静默用默认值，与原生 table.vue 同口径。
fetchTableState().catch(() => {})

// ---------- 挂载 ----------
// 根节点是一个 fragment：主体 ProjectList + 六个浮层，与 App.vue 的顺序一致。
const Root = {
  render: () => [
    h(ProjectList),
    h(NavigatorPanel),
    h(NewProjectModal),
    h(NewFolderModal),
    h(FilterPanel),
    // 🔴 RowMenu 挂在 Root 层（不在 ProjectList 里）—— 它是全屏 backdrop 覆盖层，
    //    放在列表页组件里会被 .table-card 的 overflow 裁掉。所以 @action 的落点
    //    也必须在 Root 这一层收，否则菜单点了「打开项目详情」没反应
    //    （组件只 emit，没人接 → 事件黑洞）。
    h(RowMenu, { onAction: (key) => window.dispatchEvent(new CustomEvent('eln:row-menu', { detail: { key } })) }),
    // 行菜单行动浮体（编辑 / 移动 / 访问权限 / 评论）：同样是全屏 backdrop，必须挂 Root。
    // 它读 ui.rowAction 自己显隐，不需要 Root 传业务数据进去了。
    h(RowActionModal),
    h(BulkActionBar)
  ]
}

createApp(Root)
  .component('router-link', HostRouterLink)
  .mount('#eln-project-list')
