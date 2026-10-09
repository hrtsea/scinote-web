<template>
  <div class="h-full flex items-center justify-center">
    <MenuDropdown
      :listItems="items"
      btnClasses="btn btn-light icon-btn"
      :position="'right'"
      :alwaysShow="true"
      :btnIcon="'sn-icon sn-icon-more-hori'"
      @dtEvent="handleEvent"
    ></MenuDropdown>

    <!-- 行操作模态框：除 activity（直接跳转）外，其余动作都在这里完成 -->
    <row-action-modal
      v-if="activeAction"
      :kind="activeAction.kind"
      :row="activeAction.row"
      :action="activeAction.action"
      @closed="onModalClosed"
    ></row-action-modal>
  </div>
</template>

<script>
import MenuDropdown from 'shared/menu_dropdown.vue';
import RowActionModal from './row_action_modal.vue';

// ELN 专属行菜单（参照 V1 行为）：
//   activity -> 直接跳转原生动态页；
//   edit/move/access/comment/export/archive/delete -> 打开原生同款模态框
//   （row_action_modal.vue 按动作类型复用原生 JSON 端点，不再裸发请求）。
export default {
  name: 'ElnRowMenuRenderer',
  props: {
    params: { required: true }
  },
  components: {
    MenuDropdown,
    RowActionModal
  },
  data() {
    return {
      labelMap: {
        edit: '编辑',
        access: '访问权限',
        move: '移动',
        export: '导出',
        archive: '归档',
        comment: '评论',
        activity: '动态',
        delete: '删除'
      },
      // 直接跳转的动作（不弹模态框）
      linkActions: ['activity'],
      activeAction: null
    };
  },
  computed: {
    actions() {
      return (this.params.data && this.params.data.actions) || {};
    },
    items() {
      return Object.entries(this.actions)
        .filter(([, a]) => a && a.enabled)
        .map(([key, a]) => ({
          text: this.labelMap[key] || key,
          data_e2e: `e2e-BT-rowActions-${key}`,
          emit: 'rowAction',
          params: { key, action: a }
        }));
    }
  },
  methods: {
    handleEvent(_event, option) {
      const { key, action } = option.params;
      if (this.linkActions.includes(key)) {
        if (action.url) window.location.assign(action.url);
        return;
      }
      this.activeAction = { kind: key, row: this.params.data, action };
    },
    onModalClosed() {
      const kind = this.activeAction && this.activeAction.kind;
      this.activeAction = null;
      const dt = this.params.dtComponent;
      // 仅对会改变网格数据的动作刷新表格，避免访问/评论/导出等只读动作
      // 触发整表重渲染导致行 DOM 失效（进而造成菜单句柄过期、遮罩拦截点击）。
      const mutating = ['edit', 'move', 'archive', 'delete'];
      if (dt && dt.reloadTable && mutating.includes(kind)) dt.reloadTable(false);
    }
  }
};
</script>
