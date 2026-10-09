import { createApp } from 'vue/dist/vue.esm-bundler.js';
import ResultsShow from '../../vue/shareable_links/results_show/index.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('ResultsShow', ResultsShow);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#resultsShowMount');
