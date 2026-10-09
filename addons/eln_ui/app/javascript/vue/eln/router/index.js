import { createRouter, createWebHashHistory } from 'vue-router'

// ============================================================
// 路由表
//
// ★★ 路径词汇表：**与宿主 SciNote 保持一致**（本轮改造的核心）
//
//   本表只为 **SPA 态**服务（`npm run dev` / dist 直接打开）。
//   内嵌态（挂进 SciNote 页面）**不装 vue-router** —— 每个 src/entries/*.js
//   只挂一个 view，页面跳转由 Rails 路由接管，模板里的 to 经 HostRouterLink
//   原样输出成 <a href>。
//
//   所以这里的 path 有两种，**必须分清楚，别混**：
//
//   ① 宿主也有这条页面 → path **一律照抄宿主真实路由**（见 config/routes.rb）。
//      这样同一串路径在两种模式下都指向同一张页面：
//        SPA 态  → 本表命中，页内 hash 跳转
//        内嵌态  → 透传给 Rails，整页跳转
//      好处：模板 / mock / drill 回落层从此只有一套字符串，
//      不会出现「mock 改了宿主没改」或反过来的静默死链。
//
//   ② 宿主**没有**这条页面（原型独有） → 保留原型的短路径。
//      ⚠ 不许为这类页面编一个 /eln_xxx：宿主没注册 = 内嵌态点下去必 404，
//        等于用一个假路由换一个真死链（违反「取不到就显式留白，不编造」）。
//      这类页面也不会出现在内嵌态（内嵌态不挂侧栏、不挂这些 view）。
//
//   宿主路径出处（scinote-web/config/routes.rb）：
//        ln 422  get 'projects/:project_id/eln_project_detail'   as: :project_eln_detail
//        ln 435  get 'eln_project_list'                          as: :eln_project_list
//        ln 442  get 'experiments/:id/eln_exp_detail'            as: :eln_exp_detail
//        ln 457  get 'experiments/:experiment_id/my_modules/:id/eln_task_detail'
//                                                                as: :eln_task_detail
//        ln 462  get 'eln_res_center'                            as: :eln_res_center
//        ln 474  get 'eln_res_apply/:no'                         as: :eln_res_apply_detail
//        ln 528  get 'eln_workbench'                             as: :eln_workbench
//
//   改动本表后请跑：`npm run check:paths`
//   （会用 config/routes.rb 反查，抓「编造宿主路由」和「指向不存在的页内路由」两类错）
//
// 侧栏激活态由 route.meta.sidebar 决定；**没有任何组件读 route.params**
// （详情页的 id 来自 payload 注入 / mock，不来自 URL），所以参数名只是可读性。
// ============================================================
const routes = [
  { path: '/', redirect: '/login' },

  // ---- ② 原型独有：登录（宿主有自己的登录页，不走这套） ----
  {
    path: '/login',
    name: 'login',
    component: () => import('../views/Login.vue'),
    meta: { fullscreen: true }
  },

  // ---- ① 宿主同款：工作台 ----
  {
    path: '/eln_workbench',
    name: 'workbench',
    component: () => import('../views/Workbench.vue'),
    meta: { sidebar: 'workbench', title: '工作台' }
  },

  // ---- ① 宿主同款：项目列表 ----
  {
    path: '/eln_project_list',
    name: 'projects',
    component: () => import('../views/ProjectList.vue'),
    meta: { sidebar: 'projects', title: '项目' }
  },

  // ---- ① 宿主同款：项目详情 ----
  {
    path: '/projects/:projectId/eln_project_detail',
    name: 'project-detail',
    component: () => import('../views/ProjectDetail.vue'),
    meta: { sidebar: 'projects', title: '项目详情' }
  },

  // ---- ① 宿主同款：实验详情 ----
  {
    path: '/experiments/:experimentId/eln_exp_detail',
    name: 'experiment-detail',
    component: () => import('../views/ExperimentDetail.vue'),
    meta: { sidebar: 'projects', title: '实验详情' }
  },

  // ---- ② 原型独有：实验设计视图（宿主无承载面 → OPEN，不编路由） ----
  {
    path: '/experiments/:experimentId/design',
    name: 'experiment-design',
    component: () => import('../views/ExperimentDesign.vue'),
    meta: { sidebar: 'projects', title: '实验设计视图' }
  },

  // ---- ① 宿主同款：任务详情 ----
  //   宿主把任务挂在实验之下（原生两级），故 URL 必然多一段实验 id。
  {
    path: '/experiments/:experimentId/my_modules/:taskId/eln_task_detail',
    name: 'task-detail',
    component: () => import('../views/TaskDetail.vue'),
    meta: { sidebar: 'projects', title: '任务详情' }
  },

  // ---- ② 原型独有：以下页面宿主没有对应承载面，保留原型短路径 ----
  {
    path: '/notebook',
    name: 'notebook',
    component: () => import('../views/Notebook.vue'),
    meta: { sidebar: 'projects', title: '实验记录本' }
  },
  {
    path: '/equipment',
    name: 'equipment',
    component: () => import('../views/EquipmentBooking.vue'),
    meta: { sidebar: 'equipment', title: '设备预定' }
  },
  {
    path: '/reports',
    name: 'reports',
    component: () => import('../views/Reports.vue'),
    meta: { sidebar: 'reports', title: '报表中心' }
  },
  {
    path: '/profile',
    name: 'profile',
    component: () => import('../views/Profile.vue'),
    meta: { sidebar: 'profile', title: '个人中心' }
  },
  {
    path: '/admin',
    name: 'admin',
    component: () => import('../views/SystemAdmin.vue'),
    meta: { sidebar: 'admin', title: '系统管理' }
  },
  {
    path: '/res-archive',
    name: 'res-archive',
    component: () => import('../views/ResArchive.vue'),
    meta: { sidebar: 'admin', title: '资源基础档案' }
  },

  // ---- ① 宿主同款：资源中心（宿主 /eln_res_center，页签走 ?tab=） ----
  {
    path: '/eln_res_center',
    name: 'res-center',
    component: () => import('../views/ResCenter.vue'),
    meta: { sidebar: 'resources', title: '资源中心' }
  },

  {
    path: '/inventory',
    name: 'inventory',
    component: () => import('../views/Inventory.vue'),
    meta: { sidebar: 'resources', title: '库存' }
  },
  {
    path: '/locations',
    name: 'locations',
    component: () => import('../views/Locations.vue'),
    meta: { sidebar: 'locations', title: '位置' }
  },
  {
    path: '/locations/box/:boxId',
    name: 'location-detail',
    component: () => import('../views/LocationDetail.vue'),
    meta: { sidebar: 'locations', title: '盒子详情' }
  },

  // ---- ① 宿主同款：资源申请详情（宿主参数是业务编号 :no，非纯数字） ----
  {
    path: '/eln_res_apply/:no',
    name: 'res-apply-detail',
    component: () => import('../views/ResApplyDetail.vue'),
    meta: { sidebar: 'resources', title: '资源申请详情' }
  }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

export default router
