import { createApp } from 'vue/dist/vue.esm-bundler.js';
import ProtocolShow from '../../vue/shareable_links/protocol_show/index.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

const app = createApp();
app.component('ProtocolShow', ProtocolShow);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#protocolShowMount');
