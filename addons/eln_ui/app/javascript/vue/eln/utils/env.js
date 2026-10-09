// ============================================================
// 运行模式判定 + 导航出口（全工程唯一一处）
//
// 为什么要单独立一个文件：
//   这套代码有**两种运行模式**，同一份组件要在两种模式下都对：
//     ① SPA 态   —— `npm run dev` / dist 直接打开。有 vue-router，路由表见 src/router。
//     ② 内嵌态   —— 挂进 SciNote 宿主页面（addons/*/app/views 里的 #eln-* 容器）。
//                   **不装 vue-router**（每个 entry 只 h 单个 view），页面跳转归 Rails 管。
//
//   历史写法是靠猜：`if (location.pathname.includes('eln_res_center')) { … }`。
//   这个判断的毛病是它**同时在判两件事**——模式 + 当前页——而且依赖 URL 里恰好有那段
//   字符串（SPA 态 hash 路由的 pathname 里根本没有 eln_ 段，靠的不是它，是巧合）。
//   现在改成：模式只由内嵌入口显式声明的 `window.__ELN_EMBED__` 说，一处判、一处真。
//
// ★ 与「路径词汇表」的关系（本轮核心改造）：
//   两种模式**共用同一套路径字符串**——宿主 SciNote 的真实路由。
//     SPA 态：router 的路由表就是用这些宿主路径注册的（见 src/router/index.js），
//             所以 `/eln_project_list` 在 SPA 态也是一个能命中的页内路由。
//     内嵌态：同一串路径交给 HostRouterLink 原样输出成 <a href>，Rails 接住。
//   于是模板里写一次，两种模式都对 —— 不再需要「SPA 用 /projects、真机用 /eln_project_list」
//   这种双词汇表（那个分裂就是 mock 改对了真机却点不动 / 反过来 的根因）。
// ============================================================

/**
 * 是否运行在 SciNote 宿主页面内（内嵌态）。
 * 由 src/entries/*.js 各入口**显式**声明，不做任何启发式猜测。
 */
export function isEmbedded() {
  return typeof window !== 'undefined' && window.__ELN_EMBED__ === true
}

/**
 * 统一页面导航出口。
 *
 *   内嵌态：宿主路由归 Rails 管，必须整页跳转（这里没有 vue-router）。
 *   SPA 态：交给 hash 路由；传入的字符串与内嵌态**完全相同**。
 *
 * @param {string} to 目标路径（宿主真实路径，如 '/eln_project_list'）
 * @returns {boolean} 是否发起了导航
 */
export function navigate(to) {
  if (!to || typeof to !== 'string') return false
  if (isEmbedded()) {
    window.location.href = to
    return true
  }
  window.location.hash = to.startsWith('#') ? to : `#${to}`
  return true
}

/**
 * 打开**宿主端点**（导出、附件下载等 SPA 态不存在的 URL）。
 *
 * 与 navigate 分开的原因：这些不是页面路由，SPA 态下没有对应页，不能塞进 hash 路由
 * （塞进去 = router 找不到匹配，静默空白）。SPA 态退化为新窗口打开，保持不报错。
 */
export function openHostEndpoint(url) {
  if (!url || typeof url !== 'string') return false
  if (isEmbedded()) {
    window.location.href = url
    return true
  }
  window.open(url, '_blank')
  return true
}
