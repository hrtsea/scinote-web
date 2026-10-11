import { createApp } from 'vue/dist/vue.esm-bundler.js';
import TeamsTable from '../vue/teams/table.vue';

// Mirrors app/javascript/packs/vue/helpers/turbolinks.js (inlined to keep the
// eln_ui pack build-isolated from the host packs tree).
function mountWithTurbolinks(app, target, callback = null) {
  const el = document.querySelector(target);
  if (!el) return;
  const originalHtml = el.innerHTML;
  const cacheDisabled = document.querySelector('#cache-directive');
  const event = cacheDisabled ? 'turbolinks:before-render' : 'turbolinks:before-cache';

  document.addEventListener(
    event,
    () => {
      app.unmount();
      if (document.querySelector(target)) {
        document.querySelector(target).innerHTML = originalHtml;
      }
      if (callback) callback();
    },
    { once: true }
  );

  return app.mount(target);
}

// 工作区列表入口（ADR-0034 rev3，2026-10-08）：AG Grid 版。
//
// 🔴 根组件必须是「空组件 + 全局注册 TeamTable」：挂载点 #teams-table-vue 的 innerHTML
// 就是 in-DOM 模板（<team-table :data-source="..." labels="...">），ERB 注入的 props
// 只有走 in-DOM 模板才会被解析。若直接 createApp(TeamsTable)，根组件用自己的 SFC
// 模板渲染、in-DOM 属性被整体忽略 ⇒ dataUrl 变 undefined（实测 404 /users/settings/undefined）。
// i18n 全局属性在此挂上：栈内部分页条/错误提示用 window.I18n 的老 key
// （datatable.* 双语都在已提交的 translations.js 里，可用）。
const app = createApp({});
app.component('TeamTable', TeamsTable);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#teams-table-vue');
