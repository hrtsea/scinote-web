import { createApp } from 'vue/dist/vue.esm-bundler.js';
import GlobalActivitiesTopPane from '../../vue/global_activities/top_pane.vue';
import GlobalActivitiesShowMore from '../../vue/global_activities/show_more.vue';
import GlobalActivitiesSaveFilterModal from '../../vue/global_activities/save_filter_modal.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

// 本页（global_activities/index 与 my_modules/activities 复用同一套）有几个互相独立的
// 动态区块，各自独立挂载；未渲染的挂载点（如 my_modules 页没有保存筛选模态框）自动跳过。
// 筛选器（dropdownSelector）、日期选择器（vue_legacy_datetime_picker）、
// 顶部已选标签 / 清除筛选 仍由全局 side_pane.js 负责，这里只接管 index.js 原有的三类交互。
const islands = [
  ['GlobalActivitiesTopPane', GlobalActivitiesTopPane, '#globalActivitiesTopPaneMount'],
  ['GlobalActivitiesShowMore', GlobalActivitiesShowMore, '#globalActivitiesShowMoreMount'],
  ['GlobalActivitiesSaveFilterModal', GlobalActivitiesSaveFilterModal, '#globalActivitiesSaveFilterModalMount'],
];

islands.forEach(([name, component, selector]) => {
  if (!document.querySelector(selector)) return;

  const app = createApp();
  app.component(name, component);
  app.config.globalProperties.i18n = window.I18n;
  mountWithTurbolinks(app, selector);
});
