<template>
  <!-- 登录页独立全屏，不带侧栏 -->
  <router-view v-if="isFullscreen" />

  <!-- 应用外壳：侧栏 232 + 内容区（画布 1440 基准） -->
  <div v-else class="app-shell">
    <AppSidebar />
    <main class="app-main">
      <router-view />
    </main>

    <!-- 全局浮层（项目列表页交互） -->
    <NavigatorPanel />
    <NewProjectModal />
    <FilterPanel />
    <RowMenu />
    <BulkActionBar />

    <!-- 轻提示（未展开原生入口反馈，SCN-NAV-4） -->
    <div v-if="toast.visible" class="app-toast">{{ toast.text }}</div>
  </div>
</template>

<script setup>
import { computed } from 'vue/dist/vue.esm-bundler.js'
import { useRoute } from 'vue-router'
import AppSidebar from './components/AppSidebar.vue'
import NavigatorPanel from './components/overlays/NavigatorPanel.vue'
import NewProjectModal from './components/overlays/NewProjectModal.vue'
import FilterPanel from './components/overlays/FilterPanel.vue'
import RowMenu from './components/overlays/RowMenu.vue'
import BulkActionBar from './components/overlays/BulkActionBar.vue'
import { toast } from './store/ui'

const route = useRoute()
const isFullscreen = computed(() => !!route.meta.fullscreen)
</script>

<style scoped>
.app-shell {
  display: flex;
  height: 100vh;
  overflow: hidden;
}
.app-main {
  flex: 1;
  min-width: 0;
  overflow-y: auto;
  background: var(--color-page-bg);
}
/* 轻提示：底部居中，深底白字（对齐原型 toast 形态） */
.app-toast {
  position: fixed;
  left: 50%;
  bottom: 32px;
  transform: translateX(-50%);
  z-index: 300;
  max-width: 560px;
  padding: 10px 18px;
  border-radius: 8px;
  background: #18181B;
  color: #fff;
  font-size: 13px;
  line-height: 1.5;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18);
  pointer-events: none;
}
</style>
