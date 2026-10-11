import { createApp } from "vue/dist/vue.esm-bundler.js";
import NewTeamForm from "../../vue/teams/new_form.vue";
import { mountWithTurbolinks } from "./helpers/turbolinks.js";

const app = createApp({});
app.component("NewTeamForm", NewTeamForm);
mountWithTurbolinks(app, "#new-team-form-vue");
