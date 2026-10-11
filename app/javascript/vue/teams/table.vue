<template>
  <!--
    工作区（Workspace）列表 —— AG Grid 版（ADR-0034 rev3，2026-10-08）。

    演进史：原生 jQuery DataTables（fbe24fd3d^）→ 10-08 rev「Vue 复刻原生」Bootstrap 表格
    → rev2 恢复用户需求的 ID/创建人/创建时间列 → rev3（本版）：按用户要求参照 /projects
    页面换用 AG Grid 重新实现。

    复用宿主原生 AG Grid 栈 `app/javascript/vue/shared/datatable/table.vue`
    （ADR-0035 V2.0 拍板的「薄封装 AG Grid v32.3.9」，/projects 同款）：
      · 列宽可调（defaultColDef.resizable = true，栈自带）
      · 分页条在表格下方（scrollMode 默认 'pages'：Show N rows 下拉 + 条目计数 + 页码）
      · 表头点击排序 → 服务端排序（栈对所有列注入 comparator: null，sortChanged 触发
        重新请求，order: {column, dir} 由 POST body 送达 datatable 端点）
      · 名称列自动钉左（栈对 field==='name' 的特判，与 /projects 一致）

    本仓既定约束的落点：
      · skipSaveTableState = true —— 关闭 user_settings 列状态持久化。原因：栈的自愈
        分支按「columnDefs.length + 1（选择列）」校验，我们 withCheckboxes=false 无选择列，
        会触发覆写回写；且 rev2 铁律「种子 colId 逐一 = columnDefs.field」是为持久化服务
        的，关闭后该类 bug 整体不适用。列宽调整即时生效，不跨会话记忆（用户需求为「可调」）。
      · toolbarActions = {} —— 无搜索框/无列管理工具条（原生 teams 页也无搜索框），
        栈渲染 4px 占位条，布局高度不变。
      · withCheckboxes = false —— 工作区无批量操作，与原生一致不显示选择列。
      · 表头文案仍由服务端 ERB t(...) 注入 labels prop（客户端 i18n 断链：translations.js
        是已提交的生成产物，新增 key 无法进入 bundle；而 datatable.show/rows/entries 等
        栈内自用 key 是老 key、双语都在 bundle 里，可直接用 window.I18n）。
  -->
  <DataTable
    :columnDefs="columnDefs"
    tableId="user_teams"
    :dataUrl="dataSource"
    loadMethod="post"
    :toolbarActions="{}"
    :withCheckboxes="false"
    :skipSaveTableState="true"
  ></DataTable>
</template>

<script>
// 引用宿主原生 AG Grid 栈。相对路径自 addons/eln_ui/app/javascript/vue/teams/ 上溯 6 级到仓根；
// 同仓同一 webpack 配置构建，模块解析与宿主 entry 完全一致（单例 Vue / 单份 ag-grid）。
import DataTable from '../../../../../../app/javascript/vue/shared/datatable/table.vue';
import TeamsNameRenderer from './renderers/name_renderer.vue';
import TeamsLeaveRenderer from './renderers/leave_renderer.vue';

export default {
  name: 'TeamTable',
  components: { DataTable },
  props: {
    // <team-table :data-source="..." labels="<JSON>">；labels 由服务端 ERB 的 t(...) 注入。
    dataSource: { type: String, required: true },
    labels: { type: String, default: '{}' }
  },
  computed: {
    text() {
      try {
        return JSON.parse(this.labels || '{}');
      } catch (e) {
        return {};
      }
    },
    // 7 列（rev2 列集不变）：名称 / ID / 创建人 / 创建时间 / 角色 / 成员 / 退出。
    // field = 后端 workspace_row 的 attribute 名；colId（=field）即排序请求的 order.column。
    // renderer 以直接组件引用挂载（同 /projects 的 FavoriteRenderer 用法）。
    columnDefs() {
      return [
        { field: 'name', headerName: this.text.name, cellRenderer: TeamsNameRenderer, minWidth: 160 },
        { field: 'id', headerName: this.text.id, width: 90, minWidth: 70 },
        { field: 'created_by', headerName: this.text.createdBy, minWidth: 130 },
        { field: 'created_at', headerName: this.text.createdAt, minWidth: 150 },
        { field: 'role', headerName: this.text.role, minWidth: 110 },
        { field: 'members_count', headerName: this.text.members, width: 120, minWidth: 90 },
        {
          field: 'leave',
          headerName: '',
          sortable: false,
          resizable: false,
          width: 170,
          minWidth: 150,
          cellRenderer: TeamsLeaveRenderer,
          cellRendererParams: { leaveLabel: this.text.leave, errorText: this.text.error }
        }
      ];
    }
  }
};
</script>
