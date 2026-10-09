<template>
  <!--
    V2.1 — 在 V2.0（接入原生 AG Grid 栈）基础上，按 git 历史里的宿主 projects/list.vue
    恢复「页面级缺失功能」：工具栏「新建项目 / 新建文件夹」按钮 + 点开复用宿主
    ProjectFormModal / NewFolderModal（经 webpack `host` 别名，单一真源、零复制）。

    设计约束（沿用 V2.0）：
      - 多列钉住 / 列重排 / 显隐 / 状态记忆 全部由 shared/datatable 原生支持。
      - toolbarActions 必须非空对象，否则顶部 Toolbar 不渲染、Manage Columns 入口不出现。
      - 行级动作（访问权限/移动/编辑/归档/删除/导出/评论/动态）仍由行 kebab 菜单
        （row_action_modal）覆盖，本文件不重复实现 —— 两套机制各管一层，不打架。

    新增（V2.1）：
      - UI 标志（canCreateProject / canCreateFolder / createUrls / 筛选选项）由
        /eln_project_list.json 下发（controller 的 index#format.json 已现成；注意该端点
        顶层键是小驼峰 canCreateProject / canCreateFolder / createUrls，与 grid 行字段一致）。
        挂载时拉一次，不内联 JSON、不破坏 V2 异步哲学。
      - 工具栏按钮走 DataTable 原生 emit：toolbar.vue 发 `toolbar:action`，
        table.vue 的 emitAction 按 action.name 重发为 `@create` / `@create_folder`，
        本组件监听这两个事件名（不是 @toolbar:action），分别打开宿主模态框。
      - current_folder_id / view_mode 从 URL 解析（与 controller 同款参数名），不另走 payload。
  -->
  <DataTable
    ref="dt"
    :table-id="tableId"
    :data-url="dataUrl"
    :column-defs="columnDefs"
    :toolbar-actions="toolbarActions"
    :view-renders="viewRenders"
    :per-page-options-override="perPageOptions"
    :with-pinned-columns="true"
    :skip-save-table-state="false"
    @create="onToolbarAction"
    @create_folder="onToolbarAction"
    @updateFavorite="updateFavorite"
  >
    <!-- 卡片视图：去掉 table-only 后启用。宿主表格的卡片区是具名插槽 #card，
         不传就是一片空白 —— 必须自带卡面（且必须是 ELN 行形状的卡面）。 -->
    <template #card="data">
      <!-- ⚠ 不要传 dtComponent：卡片没声明这个 prop，会被当成透传属性写到根 DOM 上，
           而它是个 Vue 实例对象 ⇒ setAttribute 报 "Cannot convert object to primitive value"。 -->
      <ProjectCard :params="data.params" />
    </template>
  </DataTable>
  <!-- 新建 / 编辑项目 —— 复用宿主模态框（host 别名，单一真源） -->
  <ProjectFormModal
    v-if="newProject"
    :create-url="ui && ui.createUrls ? ui.createUrls.project : null"
    :current-folder-id="currentFolderId"
    @close="newProject = false"
    @create="onCreated"
  />
  <!-- 新建文件夹 —— 复用宿主模态框 -->
  <NewFolderModal
    v-if="newFolder"
    :create-folder-url="ui && ui.createUrls ? ui.createUrls.folder : null"
    :current-folder-id="currentFolderId"
    :view-mode="viewMode"
    @close="newFolder = false"
    @create="onCreated"
  />
</template>

<script>
// 宿主原生 AG Grid 数据表（app/javascript/vue/shared/datatable/table.vue），
// 通过 webpack alias `shared` 引用 —— 单一真源，不复制。
import DataTable from 'shared/datatable/table.vue';
// 宿主项目模态框（经 webpack alias `host` 引用，内部相对 import 按宿主文件位置解析）。
import ProjectFormModal from 'host/projects/modals/form.vue';
import NewFolderModal from 'host/projects/modals/new_folder.vue';
// 卡片视图的卡面：用 ELN 专属卡片，不复用宿主 ProjectCard
// （宿主卡读原生行形状 urls.show / created_at，ELN 行是 detailUrl / createdAt ⇒ 空白卡 + TypeError）
import ProjectCard from './renderers/project_card.vue';
// ELN 专属渲染器（保留 ELN 行集合，自写 ELN 形状单元格）
import ElnNameRenderer from './renderers/name_renderer.vue';
import ElnOwnerRenderer from './renderers/owner_renderer.vue';
import ElnStatusRenderer from './renderers/status_renderer.vue';
import ElnProgressRenderer from './renderers/progress_renderer.vue';
import ElnMembersRenderer from './renderers/members_renderer.vue';
import ElnRowMenuRenderer from './renderers/row_menu_renderer.vue';
// 收藏星标列：直接复用宿主原生 FavoriteRenderer（shared/datatable/renderers/favorite.vue），
// 与 /projects 页同一份数据（public.favorites）+ 同一外观。渲染器点击后通过
// params.dtComponent.$emit('updateFavorite') 抛给本组件，由本组件 POST 宿主端点并刷新。
import HostFavoriteRenderer from 'shared/datatable/renderers/favorite.vue';
// 拉取 UI 标志用的 axios（宿主 custom_axios，自动注入 CSRF）
import axios from 'custom_axios';

export default {
  name: 'ElnProjectList',
  components: { DataTable, ProjectFormModal, NewFolderModal, ProjectCard, HostFavoriteRenderer },
  data() {
    return {
      // 注意：tableId 会拼成 user_settings 的 key（stateKey = `${tableId}_${viewMode}_table_state`），
      // 而 UserSetting 模型校验 key 只允许 [a-z0-9_]+（无连字符），故必须用下划线，不能用 eln-project-list。
      tableId: 'eln_project_list',
      // project_list_controller#grid 提供 AG Grid 契约 JSON
      // （{ data:[{id,type,attributes}], meta:{total_pages,total_count,filtered_count} }）
      dataUrl: '/eln_project_list/grid',
      // UI 标志（can_create_* / create_urls / 筛选选项），挂载时从 /eln_project_list.json 拉取
      ui: null,
      // 当前所在文件夹 id（从 URL ?project_folder_id=N 解析；与 controller 同名参数）
      currentFolderId: this.urlParam('project_folder_id'),
      // 视图模式（active / archived），同样从 URL 解析，默认 active
      viewMode: this.urlParam('view_mode') || 'active',
      // 模态框开关
      newProject: false,
      newFolder: false,
      columnDefs: [
        {
          // 收藏星标列（ADR-0038-A 修订：复用宿主 favorites）：field 命中 payload 下发的
          // favorite（项目行真实值；文件夹行 favorite:false 且无 urls.favorite ⇒ 宿主渲染器隐藏按钮）。
          headerName: '',
          field: 'favorite',
          colId: 'favorite',
          width: 46,
          minWidth: 46,
          pinned: 'left',
          sortable: false,
          resizable: false,
          suppressMovable: true,
          cellRenderer: HostFavoriteRenderer,
          cellStyle: { padding: 0, display: 'flex', justifyContent: 'center', alignItems: 'center' }
        },
        {
          headerName: '项目名称',
          field: 'name',
          minWidth: 240,
          // 项目名可点击进入详情（项目行）/ 下钻进文件夹（文件夹行）。
          // 目标 URL 由后端按行类型下发（row.detailUrl），前端不拼路由。
          cellRenderer: ElnNameRenderer
        },
        { headerName: 'ID', field: 'code', width: 110 },
        {
          headerName: '状态',
          field: 'status',
          width: 130,
          cellRenderer: ElnStatusRenderer
        },
        { headerName: '开始日期', field: 'startDate', width: 120 },
        { headerName: '截止日期', field: 'due', width: 120 },
        {
          headerName: '负责人',
          field: 'owner',
          width: 180,
          cellRenderer: ElnOwnerRenderer
        },
        {
          headerName: '已完成实验',
          field: 'completed',
          width: 140,
          cellRenderer: ElnProgressRenderer,
          cellRendererParams: { completedField: 'completed', totalField: 'total' }
        },
        {
          headerName: '已完成任务',
          field: 'tasksCompleted',
          width: 140,
          cellRenderer: ElnProgressRenderer,
          cellRendererParams: { completedField: 'tasksCompleted', totalField: 'tasksTotal' }
        },
        {
          headerName: '访问权限',
          field: 'members',
          width: 130,
          cellRenderer: ElnMembersRenderer
        },
        { headerName: '评论', field: 'commentsCount', width: 80 },
        { headerName: '描述', field: 'description', width: 220 },
        { headerName: '创建时间', field: 'createdAt', width: 160 },
        { headerName: '更新时间', field: 'updatedAt', width: 160 },
        { headerName: '归档日期', field: 'archivedOn', width: 120 },
        {
          // spec SCN-PROJ-LIST-10（V1.30 裁定）：操作列必须显示列名「操作」。
          // 这是**有意偏离原生**（原生该列 headerName 是空串），列管理面板里的可读名同此。
          headerName: '操作',
          field: 'rowMenu',
          width: 46,
          minWidth: 46,
          resizable: false,
          sortable: false,
          suppressMovable: true,
          cellRenderer: ElnRowMenuRenderer,
          cellStyle: {
            padding: 0,
            display: 'flex',
            justifyContent: 'center',
            alignItems: 'center',
            overflow: 'visible'
          }
        }
      ]
    };
  },
  computed: {
    // 工具栏按钮：受 can_create_* 权限门控；非空即触发原生 Toolbar 渲染。
    toolbarActions() {
      const left = [];
      if (this.ui && this.ui.canCreateProject && this.ui.createUrls) {
        left.push({
          name: 'create',
          icon: 'sn-icon sn-icon-new-task',
          label: this.i18n.t('projects.index.new'),
          type: 'emit',
          path: this.ui.createUrls.project
        });
      }
      if (this.ui && this.ui.canCreateFolder && this.ui.createUrls) {
        left.push({
          name: 'create_folder',
          icon: 'sn-icon sn-icon-folder',
          label: this.i18n.t('projects.index.new_folder'),
          type: 'emit',
          path: this.ui.createUrls.folder
        });
      }
      return { left, right: [] };
    },
    // 视图渲染模式：表格 / 卡片。宿主 Toolbar 据此渲染「表格视图 / 卡片视图」下拉切换
    // （去掉 table-only 后生效；不传 viewRenders 则切换入口不出现）。
    viewRenders() {
      return [{ type: 'table' }, { type: 'cards' }];
    },
    // 每页档位：**真源在服务端**（payload 的 pagination.perPageOptions = [0,20,50,100]，
    // 0 = 全部 / 不分页）。前端不得写死第二份 —— 宿主内置默认 [10,20,50,100] 与 spec V1.31 不符。
    // ⚠ 这里返回 [值, 标签] 对而不是裸值：0 必须渲染成「全部」而不是「0」，
    //   而 JS 翻译包是预生成产物（新 yml 键进不去），标签只能在这里自带。
    perPageOptions() {
      const p = this.ui && this.ui.pagination;
      const raw = p && Array.isArray(p.perPageOptions) ? p.perPageOptions : null;
      if (!raw) return null;
      return raw.map((v) => (
        Number(v) === 0 ? [v, '全部'] : [v, `${v} 条`]
      ));
    }
  },
  created() {
    // 拉取 UI 标志（controller index#format.json 现成下发；含 can_create_* / create_urls / 筛选选项）。
    // 仅取 UI 用到的字段，grid 行数据仍由 DataTable 异步走 /eln_project_list/grid。
    axios
      .get('/eln_project_list.json')
      .then((response) => {
        this.ui = response.data;
      })
      .catch(() => {
        this.ui = null;
      });
  },
  methods: {
    urlParam(key) {
      if (typeof window === 'undefined' || !window.location) return null;
      const v = new URLSearchParams(window.location.search).get(key);
      return v || null;
    },
    // DataTable 顶部工具栏按钮（type:'emit'）点击 → 冒泡 @toolbar:action，按 name 分派。
    onToolbarAction(action) {
      if (!action) return;
      if (action.name === 'create') {
        this.newProject = true;
      } else if (action.name === 'create_folder') {
        this.newFolder = true;
      }
    },
    // 新建项目 / 新建文件夹 成功后：关模态框 + 刷新网格（DataTable#reloadTable）。
    onCreated() {
      this.newProject = false;
      this.newFolder = false;
      if (this.$refs.dt && typeof this.$refs.dt.reloadTable === 'function') {
        this.$refs.dt.reloadTable();
      }
    },
    // 复用宿主收藏端点（与 /projects 页同源 public.favorites）：宿主 FavoriteRenderer 点击后
    // 通过 dtComponent.$emit('updateFavorite', value, params) 抛到此处，POST 对应 url 后刷新网格。
    updateFavorite(value, params) {
      const url = value ? params.data.urls.favorite : params.data.urls.unfavorite;
      if (!url) return;
      axios
        .post(url)
        .then(() => {
          if (this.$refs.dt && typeof this.$refs.dt.reloadTable === 'function') {
            this.$refs.dt.reloadTable();
          }
        })
        .catch(() => {});
    }
  }
};
</script>
