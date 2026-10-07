<template>
  <div class="teams-table-wrapper">
    <div class="teams-table-toolbar" v-if="canCreate">
      <a :href="newTeamUrl" class="btn btn-primary">新建工作区</a>
    </div>
    <div class="teams-table-search" v-if="teams.length">
      <input
        type="text"
        v-model="quickFilter"
        placeholder="搜索工作区…"
        class="form-control"
      />
    </div>
    <ag-grid-vue
      class="ag-theme-alpine"
      style="width: 100%; height: 480px;"
      :columnDefs="columnDefs"
      :rowData="teams"
      :defaultColDef="defaultColDef"
      :quickFilterText="quickFilter"
      :pagination="true"
      :paginationPageSize="10"
      @grid-ready="onGridReady"
    >
    </ag-grid-vue>
  </div>
</template>

<script>
import { AgGridVue } from 'ag-grid-vue3';

function escapeHtml(str) {
  if (str == null) return '';
  return String(str).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[c]));
}

export default {
  name: 'TeamsTable',
  components: { AgGridVue },
  props: {
    teams: { type: Array, default: () => [] },
    canCreate: { type: Boolean, default: false },
    newTeamUrl: { type: String, default: '' }
  },
  data() {
    return {
      quickFilter: '',
      gridApi: null,
      defaultColDef: {
        resizable: true,
        sortable: true
      },
      columnDefs: [
        {
          headerName: '名称',
          field: 'name',
          flex: 2,
          cellRenderer: (p) =>
            p.data && p.data.show_url
              ? `<a href="${escapeHtml(p.data.show_url)}">${escapeHtml(p.data.name)}</a>`
              : escapeHtml(p.data ? p.data.name : '')
        },
        { headerName: 'ID', field: 'id', flex: 1 },
        { headerName: '创建人', field: 'created_by', flex: 1 },
        { headerName: '创建时间', field: 'created_at', flex: 1 },
        { headerName: '角色', field: 'role', flex: 1 },
        { headerName: '成员数', field: 'members_count', flex: 1, type: 'numericColumn' },
        {
          headerName: '操作',
          colId: 'actions',
          flex: 1,
          sortable: false,
          cellRenderer: (p) =>
            p.data && p.data.can_leave
              ? `<button type="button" class="btn btn-default btn-sm leave-team-btn" data-leave="${escapeHtml(p.data.leave_url)}">退出</button>`
              : ''
        }
      ]
    };
  },
  mounted() {
    this.$el.addEventListener('click', this.onClick);
  },
  beforeUnmount() {
    this.$el.removeEventListener('click', this.onClick);
  },
  methods: {
    onGridReady(params) {
      this.gridApi = params.api;
    },
    onClick(e) {
      const btn = e.target.closest('.leave-team-btn');
      if (!btn) return;
      e.preventDefault();
      this.leaveTeam(btn.getAttribute('data-leave'));
    },
    leaveTeam(url) {
      if (!url) return;
      if (!window.confirm('确定要退出该工作区吗？此操作不可撤销。')) return;
      const token = document.querySelector('meta[name="csrf-token"]')?.content;
      fetch(url, {
        method: 'DELETE',
        headers: { 'X-CSRF-Token': token, 'Content-Type': 'application/json' },
        credentials: 'same-origin'
      })
        .then((r) => r.json())
        .then((d) => {
          window.location.href = (d && d.redirect_url) || window.location.pathname;
        })
        .catch(() => window.alert('操作失败，请稍后重试。'));
    }
  }
};
</script>
