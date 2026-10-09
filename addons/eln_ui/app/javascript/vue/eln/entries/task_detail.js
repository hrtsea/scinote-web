// ============================================================
// 任务详情页 entry（宿主 eln_ui addon 的挂载点，对应 #eln-task-detail）
//
// 与另外三个 entry（project_list / project_detail / exp_detail）同一套：
//   宿主把真实 JSON 写在 window.__ELN_TASK_DETAIL__ 上 → 这里逐字段搬进**共享的
//   reactive ui**（src/store/ui.js）→ TaskDetail.vue 读 ui 渲染。
//
// ⚠ 搬进 ui 而不是留一份局部副本，是刻意的：TaskDetail.vue 的取数口径是
//   `ui.xxx || 原型演示值`，只有写进同一个 reactive 对象，组件才会拿到真值。
//   （exp_detail.js 那段注释里点过同一个坑：塞进 store/ui 前先确认组件真的读它。）
//   另外**逐字段判 undefined**：整个 ui = injected 覆盖会把没给的字段抹成 undefined，
//   组件就落回原型演示文案（页面上又冒出「底涂剂选型 / 李组员」）。
//
// ⚠ 挂载点名 #eln-task-detail 与宿主视图
//    addons/eln_ui/app/views/scinote/eln_ui/my_module_detail/index.html.erb 一一对应。
//   改了必须真机复测：bundle 找不到节点会静默不渲染（页面 200、空白）。
//
// 面包屑：不依赖 HostRouterLink 的「/projects/:id 补后缀」改写（那条逻辑读的是
//   window.__ELN_EXP_DETAIL__.projectId，本页没有这个身份），这里直接拼宿主真路由：
//   /eln_project_list、/projects/:pid/eln_project_detail、/experiments/:eid/eln_exp_detail。
// ============================================================
import { createApp, h } from 'vue/dist/vue.esm-bundler.js'
import '../styles/tokens.css'
import { ui } from '../store/ui'
import { HostRouterLink } from './modifiers/router_link_host'
import TaskDetail from '../views/TaskDetail.vue'

const injected = window.__ELN_TASK_DETAIL__ || {}

// ---------- 页头：标题 / 状态徽标 / 面包屑 ----------
if (injected.taskName !== undefined) ui.taskName = injected.taskName
if (injected.statusCode !== undefined) ui.statusCode = injected.statusCode
if (injected.statusText !== undefined) ui.statusText = injected.statusText
if (injected.statusNative !== undefined) ui.statusNative = injected.statusNative
if (injected.statusColor !== undefined) ui.statusColor = injected.statusColor
if (injected.taskId !== undefined) ui.taskId = injected.taskId
if (injected.crumb !== undefined) {
  ui.crumb = injected.crumb
  // 面包屑三段：项目名 / 实验名 + 各自真路由（宿主拼，entry 不猜）
  if (injected.crumb.projectId !== undefined) ui.crumbProjectId = injected.crumb.projectId
  if (injected.crumb.experimentId !== undefined) ui.crumbExperimentId = injected.crumb.experimentId
}

// ---------- 任务信息卡（原生实验名 / 二开档案 purpose·plan）----------
if (injected.info !== undefined) {
  ui.info = { ...(ui.info || {}), ...injected.info }
  if (injected.info.experiment !== undefined) ui.infoExperiment = injected.info.experiment
  if (injected.info.purpose !== undefined) ui.infoPurpose = injected.info.purpose
  if (injected.info.plan !== undefined) ui.infoPlan = injected.info.plan
}
if (injected.profile !== undefined) {
  ui.profile = injected.profile
  if (injected.profile.businessCode !== undefined) ui.businessCode = injected.profile.businessCode
}

// ---------- 实验记录本（原生 Protocol 步骤，DEC-010 挂在任务层）----------
if (injected.steps !== undefined) ui.steps = injected.steps
// ---------- 结构化录入（原生 checklist，DEC-009 之前只有自由文本+清单）----------
if (injected.checklist !== undefined) ui.checklist = injected.checklist

// ---------- 讨论区 / 成果 / 关联试剂 ----------
if (injected.comments !== undefined) ui.comments = injected.comments
if (injected.results !== undefined) ui.results = injected.results
if (injected.resources !== undefined) ui.resources = injected.resources

// ---------- 右栏：任务属性 / 流程轨迹 ----------
if (injected.attributes !== undefined) ui.attributes = injected.attributes
if (injected.flow !== undefined) ui.flow = injected.flow
if (injected.flowNote !== undefined) ui.flowNote = injected.flowNote

// ---------- 审核位：显隐由原生权限位本体决定（不在这里再判一遍，避免第二套口径）----------
if (injected.review !== undefined) ui.review = injected.review

// ---------- 关闭审核（REQ-TASK-CLOSE / SCN-TASK-CLOSE）：状态 + 谁能提交/审核 + 端点 ----------
//   canSubmit 同团队成员都能提交、canReview 仅项目负责人、actionsUrl 服务端下发（前端不写死路由）。
//   真机由 my_module_detail_payload#close_review_block 注入；嵌入态无此数据 → 走空态（不回落演示）。
if (injected.closeReview !== undefined) ui.closeReview = injected.closeReview

// ---------- 挂载 ----------
// HostRouterLink 会把原型里的 <router-link>、/projects、/experiments/:id 改写成宿主路由。
createApp({ render: () => h(TaskDetail) })
  .component('router-link', HostRouterLink)
  .mount('#eln-task-detail')
