import { createApp } from 'vue/dist/vue.esm-bundler.js';
import UserRegistrationEditForms from '../../vue/user_registration_edit/index.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('UserRegistrationEditForms', UserRegistrationEditForms);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#userRegistrationEditForms');
