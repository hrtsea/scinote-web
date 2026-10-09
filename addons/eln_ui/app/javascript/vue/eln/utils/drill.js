// 下钻 URL 解析（ELN addon · 前端侧唯一出口）
//
// 为什么要有这个模块：
//   每个下钻点都要判「payload 有没有下发真实 URL」，散在 15 个视图里早晚不一致。
//   集中到这里，退化行为只有一处定义。
//
// ★★ 路径词汇表（本轮改造）：回落路径**与宿主 SciNote 真实路由同形状**。
//   宿主真实路由：
//       项目列表   /eln_project_list
//       项目详情   /projects/:project_id/eln_project_detail
//       实验详情   /experiments/:id/eln_exp_detail
//       任务详情   /experiments/:experiment_id/my_modules/:id/eln_task_detail
//   为什么回落层要跟着改（原本写的是原型短路径 /projects、/experiments/:id、/tasks/:id）：
//     SPA 态的路由表已改成宿主路径（src/router/index.js），回落层若仍是旧短路径，
//     SPA 态点击就**匹配不到任何页内路由** —— 正是那个「点了没反应、不报错」的静默死链。
//     现在两边同形状：SPA 态命中页内路由，内嵌态由 HostRouterLink 透传给 Rails。
//
// 铁律（与后端 payload 同一口径）：
//   1. **前端不写死宿主路由**。真实 URL 一律由后端 payload 下发（detailUrl）。
//   2. payload 没给（原型独立跑 / 未注入）→ 回落到**同形状**的路径，保持纯退化可演示，
//      不报错、不空白、不假装通。
//   3. 真机环境下（存在 detailUrl）一律走它，回落路径只作兜底。
//   4. 回落路径与宿主同形状 ≠ 前端在猜宿主路由：形状是**契约**（写在本文件顶部 +
//      src/router/index.js 顶部 + `npm run check:paths` 反查），不是散落各处的猜测。

/**
 * 下钻目标类型 → 回落路径模板（仅 payload 未下发 detailUrl 时用）。
 *
 * ⚠ 任务详情多一段实验 id —— 宿主把任务挂在实验之下（原生两级 URL）。
 *   缺 experimentId 时**返回空串**，由调用方决定怎么处理；这里绝不编一个假 id
 *   （编了就是一个指向别人实验的死链，比没有链接更糟）。
 */
const FALLBACK = {
  project: (row) => (row.id != null ? `/projects/${row.id}/eln_project_detail` : ''),
  experiment: (row) => (row.id != null ? `/experiments/${row.id}/eln_exp_detail` : ''),
  task: (row) => {
    // 兼容两种命名：payload 可能下发 experimentId 或 experiment_id
    const expId = row.experimentId != null ? row.experimentId : row.experiment_id
    if (row.id == null || expId == null) return ''
    return `/experiments/${expId}/my_modules/${row.id}/eln_task_detail`
  }
}

/**
 * 取一条记录的下钻地址。
 *
 * @param {object} row        payload 下发的一行记录
 * @param {string} kind       'project' | 'experiment' | 'task'
 * @returns {string} 宿主真实路径；detailUrl 缺失时返回同形状的回落路径；
 *                   连构造回落路径的必要字段都缺（如 task 缺 experimentId）时返回 ''
 */
export function drillTo(row, kind) {
  if (row && typeof row.detailUrl === 'string' && row.detailUrl.length > 0) {
    return row.detailUrl
  }
  if (!row) return ''
  const build = FALLBACK[kind]
  return build ? build(row) : ''
}

/** 是否落在真实宿主路由上（用于真机验收脚本判定「已接真数据」） */
export function isRealDrill(url) {
  return typeof url === 'string' && (url.includes('_eln_') || /\/eln_[a-z_]+/.test(url))
}

/** 面包屑：把行记录链成从项目到当前层级的面包屑数组 */
export function buildCrumbs(rows) {
  return rows.filter(Boolean).map((r) => ({ name: r.name, url: r.url || '' }))
}
