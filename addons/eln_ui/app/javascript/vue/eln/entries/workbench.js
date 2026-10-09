// ============================================================
// 工作台页 —— 可嵌入条目（供 SciNote workbench addon 挂载）
//
// 与既有 entry 同一套：
//   main.js            整套 SPA（原型独立跑）
//   project_list.js    项目列表 ← 第 1 页
//   project_detail.js  项目详情 ← 第 2 页
//   exp_detail.js      实验详情 ← 第 3 页
//   task_detail.js     任务详情 ← 第 4 页
//   res_center.js      资源中心 ← 第 5 页
//   apply_detail.js    申请详情 ← 第 6 页
//   workbench.js       工作台   ← 第 7 页（本文件）
//
// ★ 数据口径（与第六页同一条规矩：**不编造**）：
//   六块全部由后端 WorkbenchPayload 实时读库下发（注入到 window.__ELN_WORKBENCH__）：
//     meta   —— 问候语 / 角色徽章 / 未读通知条数 / 状态机真名
//     kpis   —— 小组数 / 项目任务 / 参与项目（云版 Token 卡私有化不输出）
//     todos  —— 待我审的资源申请 + 我的进行中任务（无真源的字段写 '—'）
//     dist   —— 真状态名 + **payload 下发的色值**（组件内不硬编颜色）
//     groups —— 小组名 / 组长（UserGroup 无 leader 列 → '—'）/ 真实完成率
//     entries—— 快捷入口，to 全部是宿主真实路由（前端不写死宿主路由）
//   真实取不到就渲染空态（空数组），**绝不回落** mock.js 里的画布演示值
//   （「张负责人」「¥86.4万」「62%」「18 天耗尽」都是演示值）。
// ============================================================

import { createApp, h } from 'vue/dist/vue.esm-bundler.js'
import '../styles/tokens.css'
import { workbenchPayload } from '../data/mock'
import Workbench from '../views/Workbench.vue'
import { HostRouterLink } from './modifiers/router_link_host'

const injected = window.__ELN_WORKBENCH__ || {}

// 六块逐块覆盖：子对象浅合并（proto 默认保留，服务端给的全量替换），
// 数组类（kpis/todos/dist/groups/entries）**整体替换** —— 服务端是权威口径，
// 不逐项 merge，否则「私有化不发 Token 卡」这类整块缺席会被默认数组顶回来。
if (injected.meta) workbenchPayload.meta = { ...workbenchPayload.meta, ...injected.meta }

;[
  ['kpis', injected.kpis],
  ['todos', injected.todos],
  ['dist', injected.dist],
  ['groups', injected.groups],
  ['entries', injected.entries]
].forEach(([key, value]) => {
  if (Array.isArray(value)) workbenchPayload[key] = value
})

createApp({ render: () => h(Workbench) })
  .component('router-link', HostRouterLink)
  .mount('#eln-workbench')
