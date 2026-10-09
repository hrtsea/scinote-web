// ============================================================
// 资源申请详情页 —— 可嵌入条目（供 SciNote eln_ui addon 挂载）
//
// 数据源：eln_ui_resource_applications 单条 + 关联项
// ============================================================

import { createApp, h } from 'vue/dist/vue.esm-bundler.js'
import '../styles/tokens.css'
import { applyDetailPayload } from '../data/mock'
import { ui } from '../store/ui'
import ResApplyDetail from '../views/ResApplyDetail.vue'
import { HostRouterLink } from './modifiers/router_link_host'

const injected = window.__ELN_APPLY_DETAIL__ || {}

// 整对象替换（service 返回的 6 个键全部覆盖）
if (injected.application) applyDetailPayload.application = injected.application
if (Array.isArray(injected.items)) applyDetailPayload.items = injected.items
if (Array.isArray(injected.timeline)) applyDetailPayload.timeline = injected.timeline
if (injected.approvals) applyDetailPayload.approvals = { ...applyDetailPayload.approvals, ...injected.approvals }
if (Array.isArray(injected.linkedConsumptions)) applyDetailPayload.linkedConsumptions = injected.linkedConsumptions
if (injected.meta) applyDetailPayload.meta = { ...applyDetailPayload.meta, ...injected.meta }
// ⚠ 到货验货进度（REQ-RES-RECEIPT）：**别漏这一行**。
//   漏了不会报错、不会白屏 —— 页面照常渲染，只是进度恒显示「已验 0 / 共 0」
//   （ResApplyDetail.vue 里有同形兜底对象），轮次记录永远空数组。
//   2026-10-06 实测踩过：后端 payload 顶层确实发了 receiptProgress，
//   但这个入口是**逐键白名单**合并，不在名单里的键一律丢弃 ⇒ 静默失效。
if (injected.receiptProgress) applyDetailPayload.receiptProgress = injected.receiptProgress

applyDetailPayload.notFound  = !!injected.notFound
applyDetailPayload.forbidden = !!injected.forbidden

ui.applyNotFound  = applyDetailPayload.notFound
ui.applyForbidden = applyDetailPayload.forbidden

createApp({ render: () => h(ResApplyDetail) })
  .component('router-link', HostRouterLink)
  .mount('#eln-apply-detail')
