// AI 协议解析（Import with AI）入口 pack。
//
// 对齐官方挂载方式（源码级反抽 §2）：
//   · createApp({}) 空根组件 + 内联模板（挂载点 innerHTML 作为模板）；
//   · 根组件名为 AiParserContainer（createApp({}).component('ai-parser-container', ...)）；
//   · globalProperties.i18n = window.I18n 的本地等价物（i18n 字典由服务端 ERB 注入
//     <ai-parser-container data-i18n-strings> 属性，pack 启动时解析为 this.i18n.t）；
//   · 挂载前备份 innerHTML，turbolinks 事件里 unmount + 还原（与 mountWithTurbolinks 同构）。
//
// 由宿主 webpack 自动收录（config/webpack/webpack.config.js 遍历
// addons/*/app/javascript/packs/*.js 注册为 entry），无需改宿主 entryList。
import { createApp } from 'vue/dist/vue.esm-bundler.js';
import AiParserContainer from '../vue/AiParserContainer.vue';

function mountWithTurbolinks(app, target) {
  const el = document.querySelector(target);
  if (!el) return null;
  const originalHtml = el.innerHTML;
  const cacheDisabled = document.querySelector('#cache-directive');
  const event = cacheDisabled ? 'turbolinks:before-render' : 'turbolinks:before-cache';
  document.addEventListener(
    event,
    () => {
      app.unmount();
      const again = document.querySelector(target);
      if (again) again.innerHTML = originalHtml;
    },
    { once: true }
  );
  return app.mount(target);
}

// i18n 字典：从服务端注入的 data-i18n-strings 属性解析（规避 CSP 内联脚本）。
function loadI18nStrings() {
  const containerEl = document.getElementById('aiParserContainer');
  const childEl = containerEl ? containerEl.querySelector('ai-parser-container') : null;
  const raw = childEl ? childEl.getAttribute('data-i18n-strings') : null;
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (e) {
    return {};
  }
}

function buildI18n() {
  const strings = loadI18nStrings();
  return {
    t(key, vars) {
      let str = Object.prototype.hasOwnProperty.call(strings, key) ? strings[key] : key;
      if (vars) {
        Object.keys(vars).forEach((k) => {
          str = str.replace(new RegExp(`%\\{${k}\\}|\\{${k}\\}`, 'g'), vars[k]);
        });
      }
      return str;
    }
  };
}

const app = createApp({});
app.component('ai-parser-container', AiParserContainer);
app.config.globalProperties.i18n = buildI18n();

mountWithTurbolinks(app, '#aiParserContainer');
