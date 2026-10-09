<template>
  <!-- 批量操作栏（画布 40:107）：1151×68 底#EBEDF0 圆角8 padding16 -->
  <transition name="slide-up">
    <div v-if="ui.bulkBarVisible" class="bulk-bar">
      <span class="bulk-count">已选中 {{ ui.selectedProjectIds.length }} 项</span>
      <div class="bulk-actions">
        <button class="bulk-btn" @click="clearSelection"><AppIcon name="move-arrow" :size="14" />移动</button>
        <button class="bulk-btn" @click="clearSelection"><AppIcon name="archive" :size="14" />归档</button>
        <button class="bulk-btn" @click="clearSelection"><AppIcon name="export" :size="14" />导出</button>
      </div>
      <button class="bulk-close" title="取消选择" @click="clearSelection"><AppIcon name="close" :size="14" /></button>
    </div>
  </transition>
</template>

<script setup>
import { ui, clearSelection } from '../../store/ui'
import AppIcon from '../AppIcon.vue'
</script>

<style scoped>
.bulk-bar {
  position: fixed;
  bottom: 24px;
  left: calc(var(--sidebar-width) + (100vw - var(--sidebar-width)) / 2);
  transform: translateX(-50%);
  width: min(1151px, calc(100vw - var(--sidebar-width) - 56px));
  height: 68px;
  padding: 0 16px;
  background: var(--color-bulk-bg);
  border-radius: 8px;
  box-shadow: var(--shadow-pop);
  display: flex;
  align-items: center;
  gap: 16px;
  z-index: 30;
}
.bulk-count {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.bulk-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-left: auto;
}
.bulk-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 36px;
  padding: 0 14px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 13px;
  font-weight: 500;
  color: var(--color-primary);
  transition: background 0.15s ease;
}
.bulk-btn:hover {
  background: #F9FAFB;
}
.bulk-btn svg {
  color: var(--color-primary);
}
.bulk-close {
  width: 32px;
  height: 32px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: none;
  background: transparent;
  border-radius: 6px;
  color: var(--color-text-secondary);
}
.bulk-close:hover {
  background: rgba(255, 255, 255, 0.6);
}
.slide-up-enter-active,
.slide-up-leave-active {
  transition: transform 0.2s ease, opacity 0.2s ease;
}
.slide-up-enter-from,
.slide-up-leave-to {
  transform: translateX(-50%) translateY(12px);
  opacity: 0;
}
</style>
