import { createApp } from 'vue/dist/vue.esm-bundler.js';
import UserConfirmationNew from '../../vue/user_confirmation_new/index.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('UserConfirmationNew', UserConfirmationNew);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#userConfirmationErrors');
