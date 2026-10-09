import { createApp } from 'vue/dist/vue.esm-bundler.js';
import UserInvitationEdit from '../../vue/user_invitation_edit/index.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('UserInvitationEdit', UserInvitationEdit);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#userInvitationErrors');
