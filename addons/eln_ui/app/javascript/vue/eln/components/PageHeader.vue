<template>
  <!-- 页头（画布 4:307）：导航器开关32 + 标题 20 SemiBold + 副题 12 -->
  <header class="page-header">
    <button v-if="showNavigator" class="nav-toggle" title="导航器" @click="$emit('toggle-navigator')">
      <AppIcon name="navigator" :size="16" />
    </button>
    <div class="header-text">
      <div class="title-row">
        <h1 class="title">{{ title }}</h1>
        <!-- 标题行右侧徽标（状态标签 / 角色标签 / 指标进度标签，画布 4:393 / 4:531 / 4:122） -->
        <slot name="title-extra"></slot>
      </div>
      <p v-if="subtitle" class="subtitle">{{ subtitle }}</p>
    </div>
    <!-- 页头右侧操作组：画布 4:727 / 4:534 均为 gap 8（内部按钮间距），
         与标题组之间由 .page-header 的 gap 12 隔开（画布为 0，右侧块为 hug 宽故等效）。 -->
    <div v-if="$slots.right" class="header-actions">
      <slot name="right"></slot>
    </div>
  </header>
</template>

<script setup>
import AppIcon from './AppIcon.vue'

defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  showNavigator: { type: Boolean, default: false }
})

defineEmits(['toggle-navigator'])
</script>

<style scoped>
.page-header {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}
/* 标题组占满剩余宽度 → 右侧操作组恒贴内容区右缘
   （画布实测：ProjectDetail p2 三按钮右缘 1410.5、TaskDetail p6 两按钮右缘 1411.5、
    Notebook p7 两按钮右缘 1411.5，均 = 内容区右边界 1412） */
.header-text {
  flex: 1;
  min-width: 0;
}
.nav-toggle {
  width: 32px;
  height: 32px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  color: var(--color-text-secondary);
  transition: background 0.15s ease;
  /* 画布 79:258 页头：开关与「标题组」垂直居中（不随标题行顶端对齐） */
  align-self: center;
}
.nav-toggle:hover {
  background: #F9FAFB;
  color: var(--color-text);
}
.title-row {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}
.title {
  margin: 0;
  font-size: 20px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.3;
}
.subtitle {
  margin: 4px 0 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}
</style>
