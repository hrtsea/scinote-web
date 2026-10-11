<template>
  <!--
    工作区列表「退出」列 cellRenderer（ADR-0034 rev3）。
    复刻原生 index.js 的离开流程：fetch leave_url（服务端 leave_user_team_html_path）
    → 填充服务端渲染的 #modal-leave-user-team → modal('show')。
    「能否退出」由后端 workspace_row#can_leave 判定（与 UserTeamsController#destroy
    的 last_with_permission? 同一真源）：最后一个持有 USERS_MANAGE 的人禁用按钮。
    弹窗内表单提交成功 → 整页刷新（由宿主 DataTable 组件外层无感——该绑定挂在
    document 上，见 teams/table.vue 的 bindLeaveModal）。
  -->
  <button
    type="button"
    class="btn btn-secondary btn-xs"
    data-action="leave-user-team"
    :disabled="!canLeave"
    @click="openLeaveModal"
  >
    <span class="sn-icon sn-icon-sign-out"></span>
    <span class="hidden-xs">{{ params.leaveLabel }}</span>
  </button>
</template>

<script>
export default {
  name: 'TeamsLeaveRenderer',
  props: {
    params: { type: Object, required: true }
  },
  computed: {
    canLeave() {
      return !!(this.params.data && this.params.data.can_leave && this.params.data.leave_url);
    }
  },
  methods: {
    csrfToken() {
      return document.querySelector('meta[name="csrf-token"]')?.content;
    },
    openLeaveModal() {
      const row = this.params.data;
      if (!this.canLeave || !row.leave_url) return;

      fetch(row.leave_url, {
        credentials: 'same-origin',
        headers: { Accept: 'application/json', 'X-CSRF-Token': this.csrfToken() }
      })
        .then((response) => response.json())
        .then((data) => {
          const $ = window.jQuery;
          if (!$) return;
          const modal = $('#modal-leave-user-team');
          modal.find('.modal-header .modal-title').text(data.heading);
          modal.find('.modal-body').html(data.html);
          modal.modal('show');
        })
        .catch(() => {
          window.HelperModule?.flashAlertMsg(this.params.errorText, 'danger');
        });
    }
  }
};
</script>
