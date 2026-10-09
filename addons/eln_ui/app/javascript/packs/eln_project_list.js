import { createApp } from 'vue/dist/vue.esm-bundler.js';
import ElnProjectList from '../vue/eln_project_list/list.vue';
// 全局样式（ADR-0038-D）：AG Grid 主题覆盖，scoped 到本页 #eln-project-list。
// 无 <style scoped>（要覆盖 AG Grid 自带 .ag-* DOM，scoped 的 data 属性会选不中），
// 由 webpack（MiniCssExtractPlugin）抽取为 app/assets/builds/eln_project_list.css，
// 视图用 stylesheet_link_tag 'eln_project_list' 加载。
import '../vue/eln_project_list/styles/eln_project_list.scss';

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
