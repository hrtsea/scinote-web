import { createApp } from 'vue/dist/vue.esm-bundler.js';
import WebhooksIndex from '../../vue/webhooks/index.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('WebhooksIndex', WebhooksIndex);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#webhooksIndex');
