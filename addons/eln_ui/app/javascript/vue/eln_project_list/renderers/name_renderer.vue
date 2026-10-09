<template>
  <!--
    ELN 专属：项目名称列渲染为可点击链接。
    - 项目行：detailUrl = /projects/:id/eln_project_detail（后端 ProjectListPayload 已算好）；
    - 文件夹行：detailUrl = /eln_project_list?project_folder_id=:id（下钻进文件夹）。
    两种行的 detailUrl 都由后端按真实路由下发，前端绝不自己拼宿主路由（铁律：路径词汇表只一套）。
    detailUrl 取不到时回落纯文本，不假装可点。
  -->
  <div class="flex items-center gap-1.5 h-full min-w-0">
    <a
      v-if="detailUrl"
      :href="detailUrl"
      class="truncate hover:underline"
      :title="name"
      data-e2e="e2e-CO-project-name-link"
    >{{ name }}</a>
    <span v-else class="truncate text-sn-dark-grey" :title="name">{{ name }}</span>
  </div>
</template>

<script>
// 复用 owner_renderer 同款 props 契约：AG Grid 把整行塞进 params.data，
// 其中 id / name / folder / detailUrl 都是 ProjectListPayload 行装配的字段。
export default {
  name: 'ElnNameRenderer',
  props: {
    params: { required: true }
  },
  computed: {
    row() {
      return (this.params && this.params.data) || {};
    },
    name() {
      return this.row.name || '—';
    },
    detailUrl() {
      return this.row.detailUrl || null;
    }
  }
};
</script>
