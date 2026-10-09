import { createApp } from 'vue/dist/vue.esm-bundler.js';
import LinkedinSignIn from '../../vue/users/linkedin_sign_in.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('LinkedinSignIn', LinkedinSignIn);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#linkedinSignInMount');
