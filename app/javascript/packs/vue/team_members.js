import { createApp } from 'vue/dist/vue.esm-bundler.js';
import TeamMembersTable from '../../vue/team_members/index.vue';
import { mountWithTurbolinks } from './helpers/turbolinks.js';

// Single island: the team members DataTable + its delegated action handlers.
// The invite modal itself is rendered server-side by the `shared/invite_users_modal`
// partial and wired by the global `invite_users_modal.js` (loaded via application.js);
// this island only reloads the page after a successful invite.
const app = createApp();
app.component('TeamMembersTable', TeamMembersTable);
app.config.globalProperties.i18n = window.I18n;
mountWithTurbolinks(app, '#teamMembersTableMount');
