import { createApp } from 'vue/dist/vue.esm-bundler.js';
import ReportsWizard from '../../vue/reports/wizard.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

// 报表向导：header / footer 由 Vue 渲染后 Teleport 到各自挂载点，
// 三个 tab pane 保持服务端渲染（内含大量 Rails 权限/作用域逻辑），
// Vue 只接管状态与事件，不重写 pane。
const selector = '#reportsNewWizardApp';

if (document.querySelector(selector)) {
  const app = createApp();
  app.component('ReportsWizard', ReportsWizard);
  app.config.globalProperties.i18n = window.I18n;
  mountWithTurbolinks(app, selector);
}
