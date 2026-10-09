import { createApp } from 'vue/dist/vue.esm-bundler.js';
import FluicsSettings from '../../vue/label_printers/fluics_settings.vue';
import FluicsPrinters from '../../vue/label_printers/fluics_printers.vue';
import ZebraPrinters from '../../vue/label_printers/zebra_printers.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

// 本页的三个动态区块各自独立挂载（ERB 只留静态说明文案与挂载点）。
// 未挂载的区块（如无权限时的 fluics settings）直接跳过。
const islands = [
  ['FluicsSettings', FluicsSettings, '#fluicsSettingsMount'],
  ['FluicsPrinters', FluicsPrinters, '#fluicsPrintersMount'],
  ['ZebraPrinters', ZebraPrinters, '#zebraPrintersMount'],
];

islands.forEach(([name, component, selector]) => {
  if (!document.querySelector(selector)) return;

  const app = createApp();
  app.component(name, component);
  app.config.globalProperties.i18n = window.I18n;
  mountWithTurbolinks(app, selector);
});
