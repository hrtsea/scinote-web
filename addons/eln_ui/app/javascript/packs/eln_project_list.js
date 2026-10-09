import { createApp } from 'vue/dist/vue.esm-bundler.js';
import ElnProjectList from '../vue/eln_project_list/list.vue';

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

// Root data bridge (not template expressions): Vue 3 compiles in-DOM expressions
// with a `_ctx.` prefix and only whitelists a few globals, so anything read from a
// SSR-injected `window.__ELN_*` global must be hoisted to root data here, not
// bound directly in the template.
const app = createApp(ElnProjectList);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#eln-project-list');
