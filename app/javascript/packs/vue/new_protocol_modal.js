import { createApp } from 'vue/dist/vue.esm-bundler.js';
import NewProtocolModal from '../../vue/protocols/new_protocol_modal.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('NewProtocolModal', NewProtocolModal);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#newProtocolModalMount');
