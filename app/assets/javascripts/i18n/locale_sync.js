/* global I18n */
/* eslint-env browser */

// 前端 locale 同步（宿主持有，不依赖已停用的 i18n addon）。
//
// 背景：原实现是 addons/i18n 的 scinote/i18n/application.js，它做两件事——
//   ① I18n.locale = 服务端解析出的 locale；② 注入语言切换器 UI。
// 2026-10-07 停用 i18n addon 后，app/assets/javascripts/i18n_bundle.js 里的
// `require scinote/i18n/application` 变成**死引用**（addon 停用 ⇒ 其 engine 的
// assets.precompile initializer 不跑 ⇒ Sprockets 找不到该文件 ⇒
// `rails assets:precompile` 直接 FileNotFound，构建整轮挂掉）。
// 停用核查当时只查了「宿主 app/ lib/ config/ 不引用 i18n 的 Ruby 命名空间」，
// 漏了 Sprockets 资产引用这一路。
//
// 这里只保留 ①：locale 必须与后端一致，否则 window.I18n.translations 取错语言，
// 而 eln_ui/workbench 的 Vue 页把 `window.I18n` 注入 globalProperties.i18n
// 供 shared/datatable 渲染文案 —— 错 locale 等于全站文案错。
// 值从 <meta name="scinote-locale"> 读（layouts/application.html.erb 服务端渲染，
// 比 cookie 可靠，不受 SameSite / 第三方拦截影响），cookie 只作兜底。
//
// ⚠ ② 语言切换器 UI **有意不做**：与停用 i18n addon 的决定一致（切换入口归
//   addon 管，宿主不重复实现）。要恢复切换器，正确做法是恢复 addon（见 ADR-0043）。
(function () {
  'use strict';

  var AVAILABLE_LOCALES = ['en', 'zh-CN'];
  var COOKIE_NAME = 'scinote_locale';

  function getCookie(name) {
    var escaped = name.replace(/([.$?*|{}()[\]\\/+^])/g, '\\$1');
    var match = document.cookie.match(new RegExp('(?:^|; )' + escaped + '=([^;]*)'));
    return match ? decodeURIComponent(match[1]) : null;
  }

  function metaContent(name) {
    var meta = document.querySelector('meta[name="' + name + '"]');
    return meta ? meta.getAttribute('content') : null;
  }

  function pick() {
    var fromServer = metaContent('scinote-locale');
    if (AVAILABLE_LOCALES.indexOf(fromServer) >= 0) return fromServer;

    var fromCookie = getCookie(COOKIE_NAME);
    return AVAILABLE_LOCALES.indexOf(fromCookie) >= 0 ? fromCookie : 'en';
  }

  // i18n.js 尚未加载时（require 顺序被调乱）不抛错：i18n_bundle.js 里
  // 本文件排在 i18n/translations 之后，正常顺序下 I18n 一定已定义。
  if (typeof I18n === 'undefined') return;

  I18n.locale = pick();
})();
