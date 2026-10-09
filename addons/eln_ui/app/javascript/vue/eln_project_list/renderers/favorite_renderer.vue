<template>
  <button
    v-if="!isFolder"
    type="button"
    class="eln-fav-btn"
    :class="{ 'is-starred': starred }"
    :title="title"
    @click.stop="toggle"
  >
    <i class="sn-icon" :class="starred ? 'sn-icon-star-filled' : 'sn-icon-star'"></i>
  </button>
  <span v-else class="eln-fav-btn is-disabled"></span>
</template>

<script>
// 收藏星标单元格：点击 = 乐观切换 + PATCH 后端 toggle_star 端点。
// 渲染器自带 params.api / params.node（AG Grid 注入），无需父组件传 gridApi；
// 失败则回滚本格，不整表重拉。
import axios from 'custom_axios';

export default {
  name: 'ElnFavoriteRenderer',
  props: {
    // AG Grid 单元格 params：value = row.starred，data = 整行对象，api/node 用于刷新。
    params: { type: Object, required: true }
  },
  computed: {
    starred() {
      return !!this.params.value;
    },
    isFolder() {
      return !!(this.params.data && this.params.data.folder);
    },
    title() {
      return this.starred ? '取消收藏' : '收藏';
    }
  },
  methods: {
    toggle() {
      const { data, api, node } = this.params;
      if (!data || !data.id) return;
      const next = !this.starred;
      // 乐观更新：先翻状态 + 只刷本格
      data.starred = next;
      api.refreshCells({ rowNodes: [node], columns: ['favorite'], force: true });
      axios
        .patch(`/eln_project_list/${data.id}/star`)
        .catch(() => {
          // 失败回滚
          data.starred = !next;
          api.refreshCells({ rowNodes: [node], columns: ['favorite'], force: true });
        });
    }
  }
};
</script>

<style scoped>
.eln-fav-btn {
  border: none;
  background: transparent;
  cursor: pointer;
  padding: 0;
  line-height: 1;
  color: #9aa3ad;
}
.eln-fav-btn:hover {
  color: #f5b301;
}
.eln-fav-btn.is-starred {
  color: #f5b301;
}
.eln-fav-btn.is-disabled {
  cursor: default;
  visibility: hidden;
}
</style>
