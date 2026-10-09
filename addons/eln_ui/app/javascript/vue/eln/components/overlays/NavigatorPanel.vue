<template>
  <!-- 导航器面板（画布 40:29）：332×620 白底边框圆角12 -->
  <div v-if="ui.navigatorOpen" class="overlay-backdrop" @click.self="closeNavigator">
    <div class="navigator-panel eln-card">
      <div class="panel-header">
        <span class="panel-title">导航器</span>
        <button class="close-btn" @click="closeNavigator"><AppIcon name="close" :size="16" /></button>
      </div>
      <div class="tree">
        <template v-for="node in tree" :key="node.label">
          <div
            class="tree-item"
            :class="{ active: node.active, folder: node.type === 'folder' }"
          >
            <template v-if="node.type === 'folder'">
              <AppIcon :name="node.expanded ? 'chevron-down' : 'chevron-right'" :size="16" class="ico-arrow" />
              <AppIcon name="folder" :size="16" class="ico-folder" />
            </template>
            <!-- 项目行无图标，仅留 16 占位与文件夹行图标列对齐（画布 40:45 / 40:48 / 40:57 / 40:60） -->
            <span v-else class="tree-spacer"></span>
            <span class="tree-label">{{ node.label }}</span>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ui, closeNavigator } from '../../store/ui'
import AppIcon from '../AppIcon.vue'

// 项目树（画布 40:37 树体真值：2 个文件夹分组 + 4 个项目，当前项为高温硅胶项目）
const tree = [
  { label: '粘接与涂层', type: 'folder', expanded: true },
  { label: '150°C 蒸汽环境金属粘接用高温硅胶研究', type: 'project', active: true },
  { label: '聚硅氮烷陶瓷涂层中试放大与验证', type: 'project' },
  { label: '配方开发', type: 'folder', expanded: true },
  { label: 'PP 汽车内饰件低气味配方开发', type: 'project' },
  { label: '聚硅氮烷模具陶瓷涂层工艺开发', type: 'project' }
]
</script>

<style scoped>
.overlay-backdrop {
  position: fixed;
  inset: 0;
  z-index: 40;
}
.navigator-panel {
  position: absolute;
  left: calc(var(--sidebar-width) + 28px);
  top: 96px;
  width: 332px;
  max-height: 620px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-pop);
}
.panel-header {
  height: 52px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 14px;
  border-bottom: 1px solid var(--color-divider);
}
.panel-title {
  font-size: 16px;
  font-weight: 700;
  color: var(--color-text);
}
.close-btn {
  width: 28px;
  height: 28px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: none;
  background: transparent;
  border-radius: 6px;
  color: var(--color-text-secondary);
}
.close-btn:hover {
  background: var(--color-fill-soft);
}
.tree {
  padding: 4px 8px 8px;
  overflow-y: auto;
}
.tree-item {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 36px;
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-primary);
  cursor: pointer;
  white-space: nowrap;
}
/* 文件夹行 padL8；项目行 padL32（与文件夹图标列对齐，画布 40:38 / 40:44） */
.tree-item.folder {
  padding-left: 8px;
}
.tree-item:not(.folder) {
  padding-left: 32px;
}
.tree-item svg {
  flex-shrink: 0;
  color: var(--color-primary);
}
.tree-spacer {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
}
.tree-label {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
}
.tree-item:hover {
  background: var(--color-fill-soft);
}
.tree-item.active {
  background: var(--color-active-bg);
  font-weight: 500;
}
</style>
