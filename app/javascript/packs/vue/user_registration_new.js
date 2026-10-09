import { createApp } from 'vue/dist/vue.esm-bundler.js';
import UserRegistrationNew from '../../vue/user_registration_new/index.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('UserRegistrationNew', UserRegistrationNew);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#userRegistrationErrors');
