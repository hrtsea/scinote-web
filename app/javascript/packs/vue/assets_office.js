import { createApp } from 'vue/dist/vue.esm-bundler.js';
import AssetsOffice from '../../vue/assets_office/assets_office.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

// Both assets/edit and assets/view render an identical shell and rely on the
// same office-preview behavior, so a single shared island is mounted on both
// pages' #assetsOfficeMount mount point.
const app = createApp();
app.component('AssetsOffice', AssetsOffice);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#assetsOfficeMount');
