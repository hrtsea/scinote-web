/* global I18n */
/* eslint-env browser */

// SciNote I18n addon - frontend glue
// 1. Syncs window.I18n.locale with the backend-resolved locale (cookie)
// 2. Injects a language switcher widget into every page (zero view intrusion)

(function () {
  'use strict';

  var AVAILABLE_LOCALES = ['en', 'zh-CN'];
  var COOKIE_NAME = 'scinote_locale';

  function getCookie(name) {
    var escaped = name.replace(/([.$?*|{}()[\]\\/+^])/g, '\\$1');
    var match = document.cookie.match(new RegExp('(?:^|; )' + escaped + '=([^;]*)'));
    return match ? decodeURIComponent(match[1]) : null;
  }

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : null;
  }

  function serverLocale() {
    var meta = document.querySelector('meta[name="scinote-locale"]');
    return meta ? meta.getAttribute('content') : null;
  }

  function currentLocale() {
    // 服务端解析结果优先：即使 cookie 被浏览器策略（SameSite/第三方拦截）丢弃，
    // 前端 locale 也能与服务端渲染保持一致
    var fromServer = serverLocale();
    if (AVAILABLE_LOCALES.indexOf(fromServer) >= 0) return fromServer;

    var cookieLocale = getCookie(COOKIE_NAME);
    return AVAILABLE_LOCALES.indexOf(cookieLocale) >= 0 ? cookieLocale : 'en';
  }

  function languageNames() {
    return {
      en: 'English',
      'zh-CN': '简体中文'
    };
  }

  function applyFrontendLocale() {
    if (typeof I18n === 'undefined') return;
    I18n.locale = currentLocale();
  }

  function switchTo(locale) {
    if (AVAILABLE_LOCALES.indexOf(locale) < 0) return;
    var formData = new FormData();
    formData.append('locale', locale);
    fetch('/users/settings/locale', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'X-CSRF-Token': csrfToken() },
      body: formData
    }).then(function () {
      window.location.reload();
    }).catch(function () {
      window.location.reload();
    });
  }

  function buildSwitcher() {
    var names = languageNames();
    var active = currentLocale();

    var container = document.createElement('div');
    container.id = 'scinote-i18n-switcher';
    container.setAttribute('class', 'scinote-i18n-switcher');

    var button = document.createElement('button');
    button.type = 'button';
    button.id = 'scinote-i18n-switcher-btn';
    button.setAttribute('aria-expanded', 'false');
    button.innerHTML =
      '<svg class="scinote-i18n-globe" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">' +
      '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.93 6h-2.95a15.7 15.7 0 0 0-1.38-3.56A8 8 0 0 1 18.93 8zM12 4c1.1 1.3 2 3.4 2.4 6H9.6c.4-2.6 1.3-4.7 2.4-6zM4.26 14a7.9 7.9 0 0 1 0-4h3.37a16.7 16.7 0 0 0 0 4H4.26zM5.07 16h2.95c.3 1.3.77 2.54 1.38 3.56A8 8 0 0 1 5.07 16zM12 20c-1.1-1.3-2-3.4-2.4-6h4.8c-.4 2.6-1.3 4.7-2.4 6zm3.6-1.44c.6-1.02 1.08-2.26 1.38-3.56h2.95a8 8 0 0 1-4.33 3.56zM14.97 14H9.03c-.16-1.31-.16-2.69 0-4h5.94c.16 1.31.16 2.69 0 4z"/></svg>' +
      '<span>' + names[active] + '</span>' +
      '<svg class="scinote-i18n-caret" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M7 10l5 5 5-5z"/></svg>';

    var menu = document.createElement('div');
    menu.id = 'scinote-i18n-switcher-menu';
    menu.setAttribute('role', 'menu');

    AVAILABLE_LOCALES.forEach(function (locale) {
      var item = document.createElement('button');
      item.type = 'button';
      item.setAttribute('role', 'menuitem');
      item.setAttribute('data-locale', locale);
      item.textContent = names[locale];
      if (locale === active) {
        item.setAttribute('aria-current', 'true');
        item.classList.add('is-active');
      }
      item.addEventListener('click', function () { switchTo(locale); });
      menu.appendChild(item);
    });

    container.appendChild(button);
    container.appendChild(menu);

    button.addEventListener('click', function () {
      var expanded = button.getAttribute('aria-expanded') === 'true';
      button.setAttribute('aria-expanded', String(!expanded));
      menu.classList.toggle('is-open', !expanded);
    });

    document.addEventListener('click', function (event) {
      if (!container.contains(event.target)) {
        button.setAttribute('aria-expanded', 'false');
        menu.classList.remove('is-open');
      }
    });

    return container;
  }

  function injectStyles() {
    var style = document.createElement('style');
    style.textContent = [
      '.scinote-i18n-switcher{position:fixed;right:18px;bottom:18px;z-index:2000;font-size:14px;}',
      '#scinote-i18n-switcher-btn{display:flex;align-items:center;gap:6px;padding:8px 12px;border:1px solid #d9d9d9;border-radius:20px;background:#fff;color:#2b3d51;box-shadow:0 2px 8px rgba(0,0,0,.12);cursor:pointer;font:inherit;}',
      '#scinote-i18n-switcher-btn:hover{background:#f5f7fa;}',
      '.scinote-i18n-globe{fill:#2b3d51;}',
      '.scinote-i18n-caret{fill:#9aa5b1;transition:transform .15s ease;}',
      '#scinote-i18n-switcher-btn[aria-expanded="true"] .scinote-i18n-caret{transform:rotate(180deg);}',
      '#scinote-i18n-switcher-menu{display:none;position:absolute;right:0;bottom:44px;min-width:150px;padding:4px;background:#fff;border:1px solid #e3e8ef;border-radius:8px;box-shadow:0 4px 16px rgba(0,0,0,.12);}',
      '#scinote-i18n-switcher-menu.is-open{display:block;}',
      '#scinote-i18n-switcher-menu button{display:block;width:100%;padding:8px 10px;border:0;border-radius:6px;background:transparent;color:#2b3d51;text-align:left;cursor:pointer;font:inherit;}',
      '#scinote-i18n-switcher-menu button:hover{background:#f0f4f8;}',
      '#scinote-i18n-switcher-menu button.is-active{background:#e8f1fd;color:#1565c0;font-weight:600;}'
    ].join('\n');
    document.head.appendChild(style);
  }

  function init() {
    // 语言切换器只注入到完整布局（带 meta[name="scinote-locale"] 的页面），
    // 精简页面（如 gene_sequence_assets/edit）仅做 locale 同步
    if (!serverLocale()) return;

    injectStyles();

    var hook = document.querySelector('[data-hook="application-body-end-html"]');
    var anchor = hook || document.body;
    var switcher = buildSwitcher();
    anchor.parentNode.insertBefore(switcher, anchor.nextSibling);
  }

  // 关键：locale 必须同步、立即生效，不能等到 DOMContentLoaded。
  // 页面内的 Vue pack 是 body 中的同步脚本，加载即 mount，并把 i18n.t() 的结果固化进 data()；
  // 若此时 I18n.locale 仍是默认的 en，Vue 首屏会渲染成英文且不会重渲染
  // ——表现为「站内跳转正常，浏览器刷新后部分中文变英文」。
  applyFrontendLocale();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
