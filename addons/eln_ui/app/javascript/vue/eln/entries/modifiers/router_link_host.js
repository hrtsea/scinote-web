// ============================================================
// 嵌入态共用的 router-link 替身（列表页 / 详情页 / 实验页 / 任务页共用）
//
// 为什么要替身：
//   原型组件（ProjectList.vue / ProjectDetail.vue …）模板里写了 <router-link>，
//   但挂进 SciNote 时**没有 vue-router** —— 路由归宿主 Rails 管。
//   装一个只渲染 <a href> 的等价替身，组件源码一行都不用改，
//   保持「原型 = 真机同一份组件」这条底线。
//
// ★ 2026-10-05 下钻重构：职责从「前端猜宿主路由」收窄为「原样透传」
//   老实现在这里做**前端路由改写**：
//     /projects        → /eln_project_list
//     /projects/36     → /projects/36/eln_project_detail
//     /experiments/34  → /experiments/34/eln_exp_detail
//     /tasks/67        → /experiments/:eid/my_modules/67
//   这是**前端在猜宿主路由表** —— 违反「前端不写死宿主路由」这条铁律，而且
//   漏改一处就是一个死链（历史上详情页那份副本漏改，面包屑跳回原生 /projects，
//   22:53 真机才抓到；后来又靠 window.__ELN_EXP_DETAIL__ 这种全局变量打补丁，
//   越补越脆）。
//
//   现在后端 payload 已经在每行下发**真实 URL**（project_list_payload 的
//   detailUrl / project_detail_payload 的 experiments[].detailUrl /
//   exp_detail_payload 的 tasks[].detailUrl / my_module_detail_payload 的
//   crumb.projectUrl），前端拿到的就是最终地址 —— 这里**原样输出**即可。
//
//   下方 rewrite 分支保留，但只在「组件仍在用原型路径」时兜底（原型独立跑、
//   或某个视图漏注入）。这是**退化路径**，不是主路。
//
// ★ 为什么不能删掉 rewrite 分支：
//   原型独立跑（npm run dev）时 payload 不存在，组件给的就是 /projects/:id，
//   那时这里不改写就会跳原生页。留着它，两种运行模式都对。
//
// 用法（各 entry mount 时）：
//   .component('router-link', HostRouterLink)
// ============================================================

import { h, computed } from 'vue/dist/vue.esm-bundler.js'

// ------------------------------------------------------------
// ★ 内嵌态标记（全工程唯一的运行模式判据）
//
// 为什么写在**这个模块的顶层**：这个模块本身就是「内嵌态」的判据 ——
//   SPA 入口 src/main.js 装的是真 vue-router，**不 import 本模块**；
//   7 个内嵌入口（project_list / project_detail / exp_detail / task_detail /
//   res_center / apply_detail / workbench）**全部** import 本模块来把 router-link
//   换成 <a href> 替身。所以「引到本模块」⇔「这是内嵌包」，不会漏、不会忘。
//
//   反例（为什么不用启发式判断）：曾用 `location.pathname.includes('eln_res_center')`
//   猜模式 —— 那同时在判「模式」和「当前页」两件事，且 SPA 态 pathname 里根本没有
//   eln_ 段，靠的是巧合。现在模式只由这里显式声明，src/utils/env.js#isEmbedded() 读它。
// ------------------------------------------------------------
if (typeof window !== 'undefined') window.__ELN_EMBED__ = true

export const DETAIL_SUFFIX = '/eln_project_detail'
export const LIST_PATH = '/eln_project_list'
export const EXP_DETAIL_SUFFIX = '/eln_exp_detail'
export const TASK_DETAIL_SUFFIX = '/eln_task_detail'

// 原生「任务」页的真实路由：SciNote 的任务（MyModule）挂在**实验**之下，
// 所以原生任务 URL 一定是 /experiments/:experiment_id/my_modules/:id 两级。
export const nativeTaskPath = (experimentId, taskId) =>
  experimentId && /^\d+$/.test(String(experimentId)) && /^\d+$/.test(String(taskId))
    ? `/experiments/${experimentId}/my_modules/${taskId}`
    : null

// 已经是宿主真实路由（含 eln_ 段）→ 直接透传，一个字符都不动。
const isHostRoute = (to) => typeof to === 'string' && to.includes('/eln_')

/** 只在退化路径上用：把原型 SPA 路径翻译成宿主路由
 *
 * ★ 2026-10-05 路径词汇表统一后，本函数已从「主路」彻底退为**历史兼容**：
 *   现在组件模板 / mock / drill 回落层用的**就是宿主真实路径**（含 eln_ 段），
 *   走上面的 isHostRoute 分支原样透传，压根到不了这里。
 *   留着它只为兜住漏改的旧路径 —— 宁可改写，也不要让用户点出一个 404。
 *   （谁还在用它：`npm run check:paths` 的扫描结果里，非 /eln_ 的字面内链即是线索。） */
function rewriteFallback(to) {
  if (typeof to !== 'string' || !to.length) return to
  if (to === '/projects') return LIST_PATH
  // ⚠ /projects/PR1025240：原型面包屑里这个**假项目 id 是写死的**（画布演示值），
  //   纯数字规则匹配不到它 → 原样透传 = 链到一个不存在的项目（真机实测 404）。
  const proj = to.match(/^\/projects\/(.+)$/)
  if (proj) {
    const pid = window.__ELN_EXP_DETAIL__ && window.__ELN_EXP_DETAIL__.projectId
    if (pid) return `/projects/${pid}${DETAIL_SUFFIX}`
  }
  if (/^\/projects\/\d+$/.test(to)) return `${to}${DETAIL_SUFFIX}`
  // ⚠ 只认纯数字 id（真机主键）：原型的 /tasks/MD-01 是演示值，
  //   匹配不上就原样输出，原型独立跑（npm run dev）时行为不变。
  const task = to.match(/^\/tasks\/(\d+)$/)
  if (task) {
    const expId = window.__ELN_EXP_DETAIL__ && window.__ELN_EXP_DETAIL__.experimentId
    const native = nativeTaskPath(expId, task[1])
    if (native) return native
  }
  const exp = to.match(/^\/experiments\/(\d+)$/)
  if (exp) return `/experiments/${exp[1]}${EXP_DETAIL_SUFFIX}`
  // 资源域（2026-10-04 真机实锤 404 → 修复）：资源中心申请列表点编号
  //   /res-apply/SQ-2026-0094 → /eln_res_apply/SQ-2026-0094
  //   （no 是业务编号 SQ-YYYY-NNNN，非纯数字，不能沿用 \d+ 规则）
  const apply = to.match(/^\/res-apply\/([^/?#]+)$/)
  if (apply) return `/eln_res_apply/${apply[1]}`
  // 申请详情页面包屑 / 返回申请列表 → 资源中心（同一条导航链，一起补）
  if (to === '/res-center') return '/eln_res_center'
  // 各页面包屑「工作台」：宿主路由是 /eln_workbench（不是原型的 /workbench）
  if (to === '/workbench') return '/eln_workbench'
  return to
}

export const HostRouterLink = {
  props: ['to'],
  setup(props, { slots }) {
    // 主路：payload 下发的真实 URL 原样透传；退化路：才做改写。
    const href = computed(() => {
      const to = props.to
      if (isHostRoute(to)) return to
      return rewriteFallback(to)
    })

    return () => h('a', { href: href.value }, slots.default?.())
  }
}