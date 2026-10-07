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

const app = createApp({});
app.component('TeamsTable', TeamsTable);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#teams-table-vue');
