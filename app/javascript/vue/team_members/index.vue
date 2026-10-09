<script setup>
import { getCurrentInstance, onBeforeUnmount, onMounted } from 'vue';

// Migrated 1:1 from app/assets/javascripts/users/settings/teams/show.js.
//
// NOTE on the table: the server endpoint `team_users_datatable_path(@team, format: :json)`
// returns jQuery DataTables *server-side* HTML format (columns '0'..'5' are pre-rendered
// HTML strings produced by the `users/settings/teams/user_dropdown` partial). This contract
// is incompatible with the repo's ag-grid `shared/datatable/table.vue` (JSON:API), so we keep
// the jQuery DataTables plugin and initialize it here in onMounted — the sanctioned "bridge a
// global jQuery plugin" pattern used elsewhere (zebraPrint, dropdownSelector, TinyMCE).
//
// Row HTML (names, roles, the update-role form and the destroy-user-team link) is fully
// server-generated; this island only (re)wires the document-delegated handlers and the
// DataTable instance, exactly mirroring the original Gen-1 behaviour.

const props = defineProps({
  // team_users_datatable_path(@team, format: :json)
  dataSource: { type: String, required: true },
  // can_invite_team_users?(@team)
  canInvite: { type: Boolean, default: false },
});

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

let usersDatatable = null;
let jobStatusInterval = null;

function jQuery() {
  return window.jQuery;
}

const NS = '.teamMembers'; // event namespace to avoid duplicate binding across reloads

function initUsersTable() {
  const $ = jQuery();
  if (!$) return;

  usersDatatable = $('#users-table').DataTable({
    dom: `R
      <'table-header'
        <'add-new-team-members'>
        <'filter-table'f>
        <'display-limit'l>
      >
      <'table-body't>
      <'table-footer'
        <'page-info'i>
        <'page-selector'p>
      >`,
    order: [[0, 'asc']],
    stateSave: true,
    buttons: [],
    processing: true,
    serverSide: true,
    ajax: {
      url: props.dataSource,
      type: 'POST',
    },
    colReorder: {
      fixedColumnsLeft: 1000000, // Disable reordering
    },
    columnDefs: [{
      targets: [0, 1, 2, 3, 4],
      searchable: true,
      orderable: true,
    }, {
      targets: 5,
      searchable: false,
      orderable: false,
      sWidth: '1%',
    }],
    columns: [
      { data: '0' },
      { data: '1' },
      { data: '2' },
      { data: '3' },
      { data: '4' },
      { data: '5' },
    ],
    oLanguage: {
      sSearch: window.I18n ? window.I18n.t('general.filter') : '',
    },
  });

  // Move the "add members" trigger into the DataTable toolbar, then reveal it.
  $('#add-new-team-members-button')
    .detach()
    .appendTo('.users-datatable .add-new-team-members')
    .removeClass('hidden');
  setTimeout(() => { $('#users-table').css('width', '100%'); }, 300);
}

function initUpdateRoles() {
  const $ = jQuery();
  if (!$) return;

  // Click on a "set role" entry in the user dropdown.
  $('.users-datatable')
    .off(`click${NS}`, "[data-action='submit-role']")
    .on(`click${NS}`, "[data-action='submit-role']", function () {
      const link = $(this);
      const form = link.closest('.dropdown-menu').find("form[data-id='update-role-form']");
      const hiddenField = form.find("input[data-field='role']");
      hiddenField.attr('value', link.attr('data-value'));
      form.submit();
    });

  $(document)
    .off(`ajax:success${NS}`, "[data-id='update-role-form']")
    .on(`ajax:success${NS}`, "[data-id='update-role-form']", (_e, data) => {
      if (data.new_path) {
        window.location.replace(data.new_path);
      } else {
        usersDatatable.ajax.reload();
      }
    })
    .off(`ajax:error${NS}`, "[data-id='update-role-form']")
    .on(`ajax:error${NS}`, "[data-id='update-role-form']", () => { /* TODO */ });
}

function initRemoveUsers() {
  const $ = jQuery();
  if (!$) return;

  // The destroy-user-team link (inside the row dropdown) is submitted via ujs (remote: true).
  $(document)
    .off(`ajax:success${NS}`, "[data-action='destroy-user-team']")
    .on(`ajax:success${NS}`, "[data-action='destroy-user-team']", (_e, data) => {
      const modal = $('#destroy-user-team-modal');
      const modalContent = modal.find('.modal-content');
      modalContent.html(data.html);
      modal.modal('show');
    })
    .off(`ajax:error${NS}`, "[data-action='destroy-user-team']")
    .on(`ajax:error${NS}`, "[data-action='destroy-user-team']", () => {
      window.HelperModule.flashAlertMsg(window.I18n.t('users.settings.user_teams.general_error'), 'danger');
    });

  // Submit the destroy form rendered inside the modal body.
  $('#destroy-user-team-modal')
    .off(`click${NS}`, "[data-action='submit']")
    .on(`click${NS}`, "[data-action='submit']", function () {
      window.animateSpinner();
      const btn = $(this);
      const form = btn
        .closest('.modal')
        .find('.modal-body')
        .find("form[data-id='destroy-user-team-form']");
      form.submit();
    });

  // Poll the removal job until done, then reload the table (or redirect).
  $(document)
    .off(`ajax:success${NS}`, "[data-id='destroy-user-team-form']")
    .on(`ajax:success${NS}`, "[data-id='destroy-user-team-form']", (_e, jobData) => {
      if (jobStatusInterval) clearInterval(jobStatusInterval);
      jobStatusInterval = setInterval(() => {
        $.get(`/jobs/${jobData.job_id}/status`, (data) => {
          if (data.status === 'done') {
            window.HelperModule.flashAlertMsg(jobData.success_message, 'success');
            if (jobData.redirect_url) {
              window.location.href = jobData.redirect_url;
            } else {
              usersDatatable.ajax.reload();
            }
            window.animateSpinner(null, false);
            $('#destroy-user-team-modal').modal('hide');
            clearInterval(jobStatusInterval);
            jobStatusInterval = null;
          }
          if (data.status === 'failed') {
            window.HelperModule.flashAlertMsg(window.I18n.t('users.settings.user_teams.general_error'), 'danger');
            window.animateSpinner(null, false);
            $('#destroy-user-team-modal').modal('hide');
            clearInterval(jobStatusInterval);
            jobStatusInterval = null;
          }
        });
      }, 2000);
    })
    .off(`ajax:error${NS}`, "[data-id='destroy-user-team-form']")
    .on(`ajax:error${NS}`, "[data-id='destroy-user-team-form']", () => {
      window.animateSpinner(null, false);
      window.HelperModule.flashAlertMsg(window.I18n.t('users.settings.user_teams.general_error'), 'danger');
    });
}

function initReloadPageAfterInviteUsers() {
  const $ = jQuery();
  if (!$) return;

  $('[data-id=team-invite-users-modal]')
    .off(`hidden.bs.modal${NS}`)
    .on(`hidden.bs.modal${NS}`, function () {
      // The invite modal (handled globally by invite_users_modal.js) marks itself
      // with data-invited="true" after a successful invite.
      if ($(this).attr('data-invited') !== undefined) {
        window.location.reload();
      }
    });
}

function initNameUpdateEvent() {
  const $ = jQuery();
  if (!$) return;

  $(document)
    .off(`inlineEditing:fieldUpdated${NS}`, '.settings-team-name .inline-editing-container')
    .on(`inlineEditing:fieldUpdated${NS}`, '.settings-team-name .inline-editing-container', function () {
      const newName = $(this).find('.view-mode').text();
      $('.breadcrumb-teams .active').text(newName);
      if ($('.settings-team-name').data('current-team')) {
        $('#team-switch .selected-team').text(newName);
      }
    });
}

function clearHandlers() {
  const $ = jQuery();
  if (!$) return;
  // Remove every handler this island registered (namespaced).
  $(document).off(NS);
  $('.users-datatable').off(NS);
  $('#destroy-user-team-modal').off(NS);
  $('[data-id=team-invite-users-modal]').off(NS);
  if (jobStatusInterval) {
    clearInterval(jobStatusInterval);
    jobStatusInterval = null;
  }
}

onMounted(() => {
  initUsersTable();
  initUpdateRoles();
  initRemoveUsers();
  initReloadPageAfterInviteUsers();
  initNameUpdateEvent();
});

onBeforeUnmount(() => {
  clearHandlers();
});
</script>

<template>
  <div class="users-datatable" data-e2e="e2e-CO-settings-workspace-usersTable">
    <div v-if="canInvite" id="add-new-team-members-button" class="hidden">
      <a
        href="#"
        class="btn btn-primary"
        data-trigger="invite-users"
        data-turbolinks="false"
        data-modal-id="team-invite-users-modal"
      >
        <span class="sn-icon sn-icon-new-task"></span>
        {{ i18n.t('users.settings.teams.edit.add_user') }}
      </a>
    </div>
    <table id="users-table" class="table" :data-source="dataSource">
      <thead>
        <tr>
          <th id="user-name">{{ i18n.t('users.settings.teams.edit.thead_user_name') }}</th>
          <th id="email">{{ i18n.t('users.settings.teams.edit.thead_email') }}</th>
          <th id="user-role">{{ i18n.t('users.settings.teams.edit.thead_role') }}</th>
          <th id="joined-on">{{ i18n.t('users.settings.teams.edit.thead_joined_on') }}</th>
          <th id="status">{{ i18n.t('users.settings.teams.edit.thead_status') }}</th>
          <th id="options">{{ i18n.t('users.settings.teams.edit.thead_actions') }}</th>
        </tr>
      </thead>
      <tbody></tbody>
    </table>
  </div>
</template>
