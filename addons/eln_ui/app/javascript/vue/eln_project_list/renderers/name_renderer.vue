<template>
  <!--
    ELN 专属：项目名称列渲染。
    - 项目行（folder=false）：detailUrl = /projects/:id/eln_project_detail，普通文本链接。
    - 文件夹行（folder=true，payload folder_row 下发）：
        * 左侧渲染文件夹图标（sn-icon-folder，品牌主色），强化层级辨识；
        * 名称链接进文件夹下钻（detailUrl = drillUrl，由后端按真实路由下发，前端不拼）；
        * 右侧渲染 folderInfo 徽章「x 个项目 | y 个文件夹」（payload folder_info 已算好，
          形状照原生 i18n，中文 default 兜底，见 project_list_payload.rb#folder_info）。
      两类行的链接地址都来自后端，前端绝不自己拼宿主路由（铁律：路径词汇表只一套）。
    detailUrl 取不到时回落纯文本，不假装可点。
  -->
  <div class="eln-name-cell" :class="{ 'eln-name-cell--folder': isFolder }">
    <span
      v-if="isFolder"
      class="sn-icon sn-icon-folder eln-name-cell__icon"
      aria-hidden="true"
    ></span>
    <a
      v-if="detailUrl"
      :href="detailUrl"
      class="eln-name-cell__link"
      :class="{ 'eln-name-cell__link--folder': isFolder }"
      :title="name"
      :data-e2e="isFolder ? 'e2e-CO-project-folder-link' : 'e2e-CO-project-name-link'"
    >{{ name }}</a>
    <span v-else class="eln-name-cell__text" :title="name">{{ name }}</span>
    <span
      v-if="isFolder && folderInfo"
      class="eln-name-cell__badge"
    >{{ folderInfo }}</span>
  </div>
</template>

<script>
// 复用 owner_renderer 同款 props 契约：AG Grid 把整行塞进 params.data，
// 其中 id / name / folder / detailUrl / folderInfo 都是 ProjectListPayload 行装配的字段。
export default {
  name: 'ElnNameRenderer',
  props: {
    params: { required: true }
  },
  computed: {
    row() {
      return (this.params && this.params.data) || {};
    },
    isFolder() {
      return this.row.folder === true;
    },
    name() {
      return this.row.name || '—';
    },
    detailUrl() {
      return this.row.detailUrl || null;
    },
    folderInfo() {
      return this.row.folderInfo || null;
    }
  }
};
</script>

<style scoped>
.eln-name-cell {
  display: flex;
  align-items: center;
  gap: 6px;
  height: 100%;
  min-width: 0;
  overflow: hidden;
}
.eln-name-cell__icon {
  /* 品牌主色，与状态/进度一致 */
  color: #3b99fd;
  flex-shrink: 0;
  font-size: 16px;
}
.eln-name-cell__link {
  color: inherit;
  text-decoration: none;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
}
.eln-name-cell__link:hover {
  text-decoration: underline;
}
.eln-name-cell__link--folder {
  font-weight: 600;
}
.eln-name-cell__text {
  color: #6b7280;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
}
.eln-name-cell__badge {
  flex-shrink: 0;
  margin-left: 2px;
  padding: 1px 6px;
  border-radius: 4px;
  background: #f0f2f5;
  color: #6b7280;
  font-size: 11px;
  line-height: 1.5;
  white-space: nowrap;
}
</style>
