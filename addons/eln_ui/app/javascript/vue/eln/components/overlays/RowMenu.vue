<template>
  <!-- 行操作菜单（画布 40:181）：186 宽白底边框圆角10 padding6，活动项目 7 项 -->
  <div v-if="ui.rowMenuOpen" class="menu-backdrop" @click.self="closeRowMenu" @contextmenu.prevent="closeRowMenu">
    <div
      class="row-menu"
      :style="{ left: ui.rowMenuPos.x + 'px', top: ui.rowMenuPos.y + 'px' }"
    >
      <!-- 菜单项按行动态（ui.rowMenuItems）：openRowMenu 打开时由列表页按 payload
           下发的 actions 算好，没权限的项直接不渲染 —— 照原生
           Toolbars::ProjectsService 的 compact 语义（不是渲染再置灰）。
           emit('action', key) 而不是就地调业务逻辑 —— 菜单组件不认识项目数据，
           它只负责"哪个动作被点了"，落点由列表页决定。 -->
      <button
        v-for="item in menuItems"
        :key="item.key"
        class="menu-item"
        :class="{ 'menu-item-primary': item.key === 'open' }"
        :data-e2e="'row-menu-' + item.key"
        @click="$emit('action', item.key)"
      >
        <AppIcon :name="item.icon" :size="15" />
        <span>{{ item.label }}</span>
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue/dist/vue.esm-bundler.js'
import { ui, closeRowMenu, rowMenuItems } from '../../store/ui'
import AppIcon from '../AppIcon.vue'

defineEmits(['action'])

// 打开菜单时没塞进来 items（原型独立跑）就退回默认 8 项
const menuItems = computed(() =>
  ui.rowMenuItems && ui.rowMenuItems.length ? ui.rowMenuItems : rowMenuItems
)
</script>

<style scoped>
.menu-backdrop {
  position: fixed;
  inset: 0;
  z-index: 60;
}
.row-menu {
  position: fixed;
  width: 186px;
  padding: 6px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-menu);
  box-shadow: var(--shadow-pop);
  display: flex;
  flex-direction: column;
  gap: 1px;
}
.menu-item {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 38px;
  padding: 0 10px;
  border: none;
  background: transparent;
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-text-menu);
  text-align: left;
  transition: background 0.1s ease;
}
.menu-item svg {
  color: var(--color-text-secondary);
  flex-shrink: 0;
}
.menu-item:hover {
  background: var(--color-fill-soft);
}
.menu-item:hover svg {
  color: var(--color-text);
}
/* 主动作（下钻入口）轻微强调：原生把最常用项排在首位，我们再加色重，
   否则 8 项长得全一样，用户看不出「打开详情」才是主路径。 */
.menu-item-primary {
  font-weight: 500;
}
.menu-item-primary svg {
  color: var(--color-primary, #2563eb);
}
</style>
