<template>
  <!-- 系统管理（画布 79:1088 / PRD §7.13）：左栏导航 212 + 右栏用户管理与全局功能开关 -->
  <div class="admin-page">
    <!-- 面包屑 -->
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">系统管理</span>
    </div>

    <!-- 页头 -->
    <div class="ad-head">
      <PageHeader
        title="系统管理"
        subtitle="仅单位管理员可见入口 · 非管理员直接访问显示无权限占位且不改变当前的位置（SCN-NAV-1/2）"
        show-navigator
        @toggle-navigator="ui.navigatorOpen ? closeNavigator() : openNavigator()"
      />
      <div class="ad-head-note">当前登录：单位管理员（hpxing） · 团队：高分子材料组</div>
    </div>

    <!-- 主区：左导航 + 右栏 -->
    <div class="ad-main">
      <!-- 左导航 -->
      <aside class="ad-nav eln-card">
        <button
          v-for="n in navs"
          :key="n.key"
          class="ad-nav-item"
          :class="{ active: activeNav === n.key }"
          @click="onNav(n)"
        >{{ n.label }}</button>
      </aside>

      <!-- 右栏 -->
      <div class="ad-content">
        <!-- 卡 1：用户管理 -->
        <section id="ad-users" class="eln-card ad-card">
          <div class="ad-card-head">
            <div class="ad-card-title">用户管理</div>
            <button class="eln-btn-primary"><AppIcon name="plus" :size="14" />新建用户</button>
          </div>
          <div class="ad-tools">
            <div class="ad-search">
              <AppIcon name="search" :size="14" />
              <input placeholder="搜索用户名 / 姓名 / 邮箱…" v-model="userKeyword" />
            </div>
            <button class="rp-chip">全部角色 <span class="rp-caret">▾</span></button>
          </div>
          <table class="eln-table">
            <thead>
              <tr>
                <th class="eln-th">用户名</th>
                <th class="eln-th">姓名</th>
                <th class="eln-th">邮箱</th>
                <th class="eln-th">角色</th>
                <th class="eln-th">状态</th>
                <th class="eln-th"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="u in filteredUsers" :key="u.username" :class="{ 'ad-row-disabled': !u.active }">
                <td class="eln-td" :class="{ 'ad-text-disabled': !u.active }">{{ u.username }}</td>
                <td class="eln-td" :class="{ 'ad-text-disabled': !u.active }">{{ u.name }}</td>
                <td class="eln-td" :class="{ 'ad-text-disabled': !u.active }">{{ u.email }}</td>
                <td class="eln-td">{{ u.role }}</td>
                <td class="eln-td">
                  <span class="status-dot" :style="{ background: u.active ? '#5EC66F' : '#A1A1AA' }"></span>
                  <span :class="u.active ? 'ad-on' : 'ad-off'">{{ u.active ? '启用' : '停用' }}</span>
                </td>
                <td class="eln-td ad-more">⋯</td>
              </tr>
            </tbody>
          </table>
          <div class="ad-footnote">
            共 5 个账号 · 业务角色与 SciNote RBAC 映射见 REQ-ROLE-MAP（DEC-007）：单位管理员 = 团队 Owner，项目负责人 / 小组组长 /
            组员按项目级具权限；账号停用后 Token 失效，但历史操作日志与花费归因（RepositoryLedgerRecord.user_id）保留不变。
          </div>
        </section>

        <!-- 卡 2：全局功能开关 -->
        <section id="ad-flags" class="eln-card ad-card">
          <div class="ad-card-head">
            <div class="ad-card-title">全局功能开关</div>
            <div class="ad-card-note">采用原生 ApplicationSettings 语义 · 关闭后入口隐藏并提示不可用</div>
          </div>
          <table class="eln-table">
            <thead>
              <tr>
                <th class="eln-th">功能模块</th>
                <th class="eln-th">配置标识</th>
                <th class="eln-th">状态</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="f in flags" :key="f.key">
                <td class="eln-td">{{ f.label }}</td>
                <td class="eln-td ad-key">{{ f.key }}</td>
                <td class="eln-td">
                  <span class="status-dot" :style="{ background: f.on ? '#5EC66F' : '#A1A1AA' }"></span>
                  <span :class="f.on ? 'ad-on' : 'ad-off'">{{ f.on ? '已开启' : '未开启' }}</span>
                </td>
              </tr>
            </tbody>
          </table>
          <div class="ad-footnote">
            共 6 个模块 · 关闭的模块在左侧导航隐藏入口并弹出不可用提示，不得静默失效（SCN-NAV-4）；
            ai_eln 引擎开关对应 Scinote::AiEln.enabled?（默认 off），开启后 AI 能力（任务书解析 / 实验记录本 / 实验设计与配方优化）
            开放（REQ-AI / §7.10）。
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import { useRouter } from 'vue-router'
import AppIcon from '../components/AppIcon.vue'
import PageHeader from '../components/PageHeader.vue'
import { ui, openNavigator, closeNavigator } from '../store/ui'

const router = useRouter()

const navs = [
  { key: 'ad-users', label: '用户管理' },
  { key: 'ad-roles', label: '角色与权限' },
  { key: 'ad-archive', label: '资源基础档案', goto: '/res-archive' },
  { key: 'ad-flags', label: '全局功能开关' },
  { key: 'ad-logs', label: '操作日志' }
]
const activeNav = ref('ad-users')

const userKeyword = ref('')
const users = [
  { username: 'hpxing', name: '邢海平', email: 'hpxing@lab.cn', role: '单位管理员', active: true },
  { username: 'zhangwei', name: '张伟', email: 'zhangwei@lab.cn', role: '项目负责人', active: true },
  { username: 'lina', name: '李娜', email: 'lina@lab.cn', role: '小组组长', active: true },
  { username: 'wangqiang', name: '王强', email: 'wangqiang@lab.cn', role: '组员', active: true },
  { username: 'zhaolei', name: '赵磊', email: 'zhaolei@lab.cn', role: '组员', active: false }
]
const filteredUsers = computed(() => {
  const k = userKeyword.value.trim().toLowerCase()
  if (!k) return users
  return users.filter(u =>
    u.username.toLowerCase().includes(k) || u.name.includes(k) || u.email.toLowerCase().includes(k)
  )
})

const flags = [
  { label: '库存管理（Inventories）', key: 'stock_management_enabled', on: true },
  { label: 'Item locations 存放位置', key: 'storage_locations_enabled', on: true },
  { label: '设备排程（Equipment scheduling）', key: 'equipment_bookings_enabled', on: true },
  { label: '表单（Forms）', key: 'forms_enabled', on: false },
  { label: '标签模板（Label templates）', key: 'label_templates_enabled', on: false },
  { label: 'AI 助手（ai_eln 引擎）', key: 'Scinote::AiEln.enabled?', on: false }
]

function onNav(n) {
  if (n.goto) {
    router.push(n.goto)
    return
  }
  const el = document.getElementById(n.key)
  if (el) {
    activeNav.value = n.key
    el.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }
}
</script>

<style scoped>
.admin-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:1091 内容区 gap 16 */
}
.breadcrumb {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
}
.crumb-link {
  color: var(--color-placeholder);
  text-decoration: none;
}
.crumb-link:hover {
  color: var(--color-primary);
}
.crumb-current {
  color: var(--color-placeholder);
  font-weight: 400;
}
.crumb-sep {
  color: var(--color-placeholder);
}
.ad-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.ad-head-note {
  font-size: 12px;
  color: var(--color-placeholder); /* 画布 79:1099 权限提示 #A1A1AA */
  text-align: right;
  line-height: 1.6;
  padding-top: 4px;
}

/* 主区两栏 */
.ad-main {
  display: flex;
  align-items: flex-start;
  gap: 20px;
}
.ad-nav {
  width: 212px;
  flex-shrink: 0;
  padding: 8px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  position: sticky;
  top: 28px;
}
.ad-nav-item {
  height: 40px;
  padding: 0 12px;
  background: none;
  border: none;
  border-radius: var(--radius-small);
  font-size: 13px;
  color: var(--color-text-menu);
  text-align: left;
}
.ad-nav-item:hover {
  background: var(--color-fill-soft);
}
.ad-nav-item.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}

/* 右栏 */
.ad-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
/* 卡片（画布 79:1091 区：padding=0，内缩下沉到卡头 / 工具条 / 表格单元格 / 卡尾） */
.ad-card {
  padding: 0;
  overflow: hidden;
}
/* 卡头（画布 h56 / padding 0 20 / 垂直居中） */
.ad-card-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  height: 56px;
  padding: 0 20px;
}
.ad-card-title {
  font-size: 14px;
  font-weight: 600;
}
.ad-card-note {
  font-size: 12px;
  color: var(--color-text-secondary);
}

/* 工具行 */
.ad-tools {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 14px;
  padding: 0 20px;
}
.ad-search {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
  height: 36px;
  padding: 0 12px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-card);
  color: var(--color-text-secondary);
}
.ad-search input {
  flex: 1;
  border: none;
  outline: none;
  background: none;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
}
.rp-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  padding: 0 14px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  font-size: 13px;
  color: var(--color-text);
}
.rp-chip:hover {
  background: #F9FAFB;
}
.rp-caret {
  font-size: 10px;
  color: var(--color-text-secondary);
}

/* 表格 */
.ad-on {
  color: #3F9E52;
}
.ad-off {
  color: var(--color-placeholder);
}
.ad-text-disabled {
  color: var(--color-placeholder);
}
.ad-more {
  color: var(--color-text-secondary);
  text-align: center;
}
.ad-key {
  font-family: var(--font-en);
  font-size: 12px;
  color: var(--color-text-secondary);
}
.ad-footnote {
  margin: 12px 20px 14px;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
  background: var(--color-fill-soft);
  border-radius: var(--radius-small);
  padding: 10px 14px;
}
</style>
