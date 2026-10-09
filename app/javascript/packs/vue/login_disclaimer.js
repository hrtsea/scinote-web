import { createApp } from 'vue/dist/vue.esm-bundler.js';
import LoginDisclaimer from '../../vue/users/login_disclaimer.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('LoginDisclaimer', LoginDisclaimer);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#loginDisclaimerMount');
