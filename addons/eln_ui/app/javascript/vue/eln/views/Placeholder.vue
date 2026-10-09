<template>
  <!-- 侧栏占位页（报表中心 / 个人中心 / 系统管理） -->
  <div class="placeholder">
    <div class="ph-card">
      <div class="ph-icon"><AppIcon :name="icon" :size="24" /></div>
      <div class="ph-title">{{ title }}</div>
      <div class="ph-desc">该模块在 V1.8 视觉稿中规划为侧栏入口，页面内容暂未设计，后续版本补充。</div>
      <router-link to="/eln_workbench" class="ph-back">返回工作台</router-link>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue/dist/vue.esm-bundler.js'
import { useRoute } from 'vue-router'
import AppIcon from '../components/AppIcon.vue'

const route = useRoute()
const title = computed(() => route.meta.title || '页面')
const icon = computed(
  () => ({ reports: 'chart', profile: 'user', admin: 'settings' }[route.meta.sidebar] || 'folder')
)
</script>

<style scoped>
.placeholder {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 28px;
}
.ph-card {
  width: 360px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 40px 32px;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  gap: 10px;
}
.ph-icon {
  width: 56px;
  height: 56px;
  border-radius: 14px;
  background: var(--color-active-bg);
  color: var(--color-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 4px;
}
.ph-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--color-text);
}
.ph-desc {
  font-size: 13px;
  color: var(--color-text-secondary);
  line-height: 1.7;
}
.ph-back {
  margin-top: 10px;
  font-size: 13px;
  font-weight: 500;
  color: var(--color-primary);
}
</style>
