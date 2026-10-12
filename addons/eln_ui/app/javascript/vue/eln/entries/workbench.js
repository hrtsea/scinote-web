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
//     meta     —— 问候语 / 角色徽章 / 更新时间 / 未读通知条数
//     todos    —— 待办事项：我的未完成任务（逾期置顶）+ 我的申请待验货
//     approvals—— 审批事项：待我审（资源申请初审/终审、任务关闭、到货验收，名单真源判定）
//     projects —— 进行中的项目：参与 ∩ 活动（与项目列表页同一真源）
//     links    —— 「查看全部」目标（只接已有承载面，无承载面 ⇒ nil）
//     totals   —— 三区真实总数（超 20 条时「共 M 条」用）
//   真实取不到就渲染空态（空数组），**绝不回落** mock.js 里的画布演示值
//   （「张负责人」「EPP 泡沫增韧体系开发」都是演示值）。
// ============================================================

import { createApp, h } from 'vue/dist/vue.esm-bundler.js'
import '../styles/tokens.css'
import { workbenchPayload } from '../data/mock'
import Workbench from '../views/Workbench.vue'
import { HostRouterLink } from './modifiers/router_link_host'

const injected = window.__ELN_WORKBENCH__ || {}

// 逐块覆盖：子对象浅合并（proto 默认保留，服务端给的全量替换），
// 数组类（todos/approvals/projects）**整体替换** —— 服务端是权威口径，
// 不逐项 merge，否则「某类单整块缺席」会被默认数组顶回来。
if (injected.meta) workbenchPayload.meta = { ...workbenchPayload.meta, ...injected.meta }

;[
  ['todos', injected.todos],
  ['approvals', injected.approvals],
  ['projects', injected.projects]
].forEach(([key, value]) => {
  if (Array.isArray(value)) workbenchPayload[key] = value
})

// links / totals 是对象块：服务端给了就整体替换（含 nil 键的显式留白语义）。
if (injected.links) workbenchPayload.links = { ...injected.links }
if (injected.totals) workbenchPayload.totals = { ...injected.totals }

createApp({ render: () => h(Workbench) })
  .component('router-link', HostRouterLink)
  .mount('#eln-workbench')
