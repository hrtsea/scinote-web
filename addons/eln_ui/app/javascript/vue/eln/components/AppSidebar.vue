<template>
  <!-- App/Sidebar（画布 4:161）：232 宽 / padding16 / 白底 / 纵向 gap10；收起态 68 图标栏（画布 63:56） -->
  <aside class="sidebar" :class="{ collapsed }">
    <!-- 品牌区（画布 4:162）：纵向 gap3 = 品牌行 h28（Logo28 + 标题 15 SemiBold + 切换钮）+ 系统副题
         副题左缘与 Logo 对齐（画布 4:166 与 4:164 同 x），**不**缩进到标题下 -->
    <div class="brand">
      <div class="brand-row">
        <div class="brand-logo">
          <AppIcon name="flask" :size="16" />
        </div>
        <div v-if="!collapsed" class="brand-title">ELN 系统</div>
        <button
          class="toggle-btn sm"
          :title="collapsed ? '展开侧边栏' : '收起侧边栏'"
          @click="toggleCollapse"
        >
          <AppIcon name="chevron-left" :size="15" :class="{ flip: collapsed }" />
        </button>
      </div>
      <div v-if="!collapsed" class="brand-sub">科研实验过程数字化平台</div>
    </div>

    <div class="divider"></div>

    <!-- 分组：研发工作 —— 十项原生入口，按原生顺序（spec REQ-SHELL / PRD §7.1） -->
    <nav class="nav">
      <div v-if="!collapsed" class="nav-group-label">研发工作</div>
      <template v-for="item in workItems" :key="item.key">
        <router-link
          v-if="!item.native"
          :to="item.to"
          class="nav-item"
          :class="{ active: isActive(item.key) }"
          :title="collapsed ? item.label : undefined"
        >
          <AppIcon :name="item.icon" :size="18" />
          <span v-if="!collapsed">{{ item.label }}</span>
        </router-link>
        <!-- 未展开的原生入口：必须可点击且给出明确反馈（SCN-NAV-4），不得静默失败 -->
        <button
          v-else
          type="button"
          class="nav-item"
          :title="collapsed ? item.label : undefined"
          @click="showToast('原生功能，本原型未展开：' + item.label)"
        >
          <AppIcon :name="item.icon" :size="18" />
          <span v-if="!collapsed">{{ item.label }}</span>
        </button>
      </template>

      <!-- 分组：系统（画布与「研发工作」同层同 gap10，无额外上边距） -->
      <div v-if="!collapsed" class="nav-group-label">系统</div>
      <div v-else class="divider" style="margin: 8px 0"></div>
      <router-link
        v-for="item in sysItems"
        :key="item.key"
        :to="item.to"
        class="nav-item"
        :class="{ active: isActive(item.key) }"
        :title="collapsed ? item.label : undefined"
      >
        <AppIcon :name="item.icon" :size="18" />
        <span v-if="!collapsed">{{ item.label }}</span>
      </router-link>
    </nav>

    <!-- 用户卡片（54 高 #F4F4F5 圆角10；收起时仅头像） -->
    <div class="user-card" :title="collapsed ? '张负责人 · 项目负责人 Owner' : undefined">
      <div class="user-avatar">张</div>
      <div v-if="!collapsed" class="user-text">
        <div class="user-name">张负责人</div>
        <div class="user-role">项目负责人 · Owner</div>
      </div>
    </div>
  </aside>
</template>

<script setup>
import { ref } from 'vue/dist/vue.esm-bundler.js'
import { useRoute } from 'vue-router'
import AppIcon from './AppIcon.vue'
import { showToast } from '../store/ui'

const route = useRoute()

// 十项原生入口（spec REQ-SHELL / PRD §7.1，按原生顺序）：
// Dashboard · Projects · Inventories · Item locations · Equipment scheduling ·
// Forms · Protocol templates · Label templates · Reports · Global activities
// 「实验任务」不再是独立入口——实验/任务页统一高亮「项目」（SCN-NAV-5）。
// ★ 路径词汇表：宿主也有的页面用**宿主真实路由**（workbench / projects / res-center），
//   宿主没有承载面的原型页保留短路径（locations / equipment / reports / profile / admin）。
//   依据与出处见 src/router/index.js 顶部；改完请跑 `npm run check:paths`。
const workItems = [
  { key: 'workbench', label: '工作台', icon: 'home', to: '/eln_workbench' },
  { key: 'projects', label: '项目', icon: 'folder', to: '/eln_project_list' },
  { key: 'resources', label: '资源中心', icon: 'book', to: '/eln_res_center' },
  { key: 'locations', label: '位置', icon: 'pin', to: '/locations' },
  { key: 'equipment', label: '设备排程', icon: 'cpu', to: '/equipment' },
  { key: 'forms', label: '表单', icon: 'clipboard', native: true },
  { key: 'protocols', label: '协议模板', icon: 'book-open', native: true },
  { key: 'labels', label: '标签模板', icon: 'tag', native: true },
  { key: 'reports', label: '报表中心', icon: 'chart', to: '/reports' },
  { key: 'activities', label: '全局活动', icon: 'activity', native: true }
]

// 原生在顶栏的两项（个人中心←头像下拉、系统管理←仅管理员可见入口）；
// 本稿为竖向侧栏外壳，故落在此处。
const sysItems = [
  { key: 'profile', label: '个人中心', icon: 'user', to: '/profile' },
  { key: 'admin', label: '系统管理', icon: 'settings', to: '/admin' }
]

const collapsed = ref(
  location.search.includes('sb=1') ||
  localStorage.getItem('eln-sidebar-collapsed') === '1'
)

function toggleCollapse() {
  collapsed.value = !collapsed.value
  localStorage.setItem('eln-sidebar-collapsed', collapsed.value ? '1' : '0')
}

function isActive(key) {
  return route.meta.sidebar === key
}
</script>

<style scoped>
.sidebar {
  width: var(--sidebar-width);
  height: 100vh;
  flex-shrink: 0;
  background: var(--color-card);
  border-right: 1px solid var(--color-border);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  overflow-y: auto;
  transition: width 0.18s ease, padding 0.18s ease;
}
.sidebar.collapsed {
  width: 68px;
  padding: 16px 10px;
}

/* 品牌区（画布 4:162）：纵向 gap3 = 品牌行 + 副题（全宽，左缘与 Logo 对齐） */
.brand {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
/* 品牌行（4:163）：Logo28 + 标题 gap10；切换钮为本稿保留项（画布无，用户拍板保留） */
.brand-row {
  display: flex;
  align-items: center;
  gap: 10px;
}
/* 收起态：小 Logo 左、切换钮右（同一位置常驻） */
.sidebar.collapsed .brand-row {
  justify-content: space-between;
}
.sidebar.collapsed .brand-logo {
  width: 24px;
  height: 24px;
  border-radius: 7px;
}
.sidebar.collapsed .brand-logo svg {
  width: 14px;
  height: 14px;
}
.brand-logo {
  width: 28px;
  height: 28px;
  border-radius: 8px;
  background: var(--color-primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.brand-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.2;
  white-space: nowrap;
}
.brand-sub {
  font-size: 11px;
  color: var(--color-placeholder);
  line-height: 1.3;
  white-space: nowrap;
}
.divider {
  height: 1px;
  background: var(--color-divider);
  flex-shrink: 0;
}

/* 导航（画布：全部条目是侧栏直接子节点，统一 gap10 → 项距 pitch 48） */
.nav {
  display: flex;
  flex-direction: column;
  gap: 10px;
  flex: 1;
}
.nav-group-label {
  font-size: 11px;
  font-weight: 500;
  color: var(--color-placeholder);
  white-space: nowrap;
}
.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 38px;
  padding: 0 10px;
  border-radius: 8px;
  font-size: 13px;
  color: var(--color-text-nav);
  text-decoration: none;
  white-space: nowrap;
  transition: background 0.12s ease, color 0.12s ease;
}
.nav-item svg {
  color: var(--color-text-secondary);
  flex-shrink: 0;
}
.nav-item:hover {
  background: #F4F4F5;
}
.nav-item.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 600;
}
/* 画布：选中项图标不变色（恒 #71717A，只有底 + 字变） */
/* 未展开的原生入口（button 形态，与链接项视觉完全一致） */
button.nav-item {
  width: 100%;
  border: none;
  background: transparent;
  font-family: inherit;
  text-align: left;
  cursor: pointer;
  flex-shrink: 0;
  appearance: none;
}
/* 收起态：纯图标居中（画布 63:61 规格 40 高圆角8） */
.sidebar.collapsed .nav-item {
  height: 40px;
  padding: 0;
  justify-content: center;
}

.toggle-btn {
  width: 100%;
  height: 36px;
  border: none;
  background: transparent;
  border-radius: 8px;
  color: var(--color-text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  flex-shrink: 0;
  transition: background 0.12s ease, color 0.12s ease;
}
.toggle-btn.sm {
  width: 20px;
  height: 20px;
  border-radius: 5px;
}
.sidebar.collapsed .toggle-btn.sm svg {
  width: 13px;
  height: 13px;
}
.toggle-btn:hover {
  background: var(--color-fill-soft);
  color: var(--color-text);
}
.toggle-btn .flip {
  transform: rotate(180deg);
}

.user-card {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 54px;
  padding: 0 10px;
  background: var(--color-fill-soft);
  border-radius: 10px;
  flex-shrink: 0;
}
.sidebar.collapsed .user-card {
  justify-content: center;
  padding: 0;
}
.user-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: var(--color-avatar-bg);
  color: var(--color-avatar-text);
  font-size: 13px;
  font-weight: 500;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.user-text {
  min-width: 0;
}
.user-name {
  font-size: 13px;
  color: var(--color-text);
  line-height: 1.2;
  white-space: nowrap;
}
.user-role {
  font-size: 11px;
  color: var(--color-text-secondary);
  line-height: 1.3;
  margin-top: 1px;
  white-space: nowrap;
}
</style>
