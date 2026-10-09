<template>
  <!-- Item locations 位置列表（画布 79:556 / PRD §7.14 · DEC-016） -->
  <div class="lc-page">
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/eln_res_center" class="crumb-link">资源中心</router-link>
      <span class="crumb-sep">/</span>
      <!-- 层级位置条 STATE-LOC-TREE-CRUMB：钻取后「位置」变可回跳链接，逐级可回溯 -->
      <router-link v-if="crumbPath.length" to="/locations" class="crumb-link" @click.prevent="goTo(0)">位置</router-link>
      <span v-else class="crumb-current">位置</span>
      <template v-for="(c, i) in crumbPath" :key="c.id">
        <span class="crumb-sep">/</span>
        <router-link
          v-if="i < crumbPath.length - 1"
          to="/locations"
          class="crumb-link"
          @click.prevent="goTo(i + 1)"
        >{{ c.name }}</router-link>
        <span v-else class="crumb-current">{{ c.name }}</span>
      </template>
    </div>

    <div class="lc-head">
      <PageHeader
        title="Locations 位置"
        subtitle="原生 storage_locations 非容器节点视图 · 两级下钻：非容器行 → 子级列表，容器行 → 盒子详情"
        show-navigator
        @toggle-navigator="ui.navigatorOpen ? closeNavigator() : openNavigator()"
      />
      <div class="lc-head-note">结构维护仅单位管理员 · 读权限对全体登录角色开放（REQ-LOC-AUDIT）</div>
    </div>

    <!-- 工具栏 -->
    <div class="lc-toolbar">
      <div class="lc-tool-left">
        <button class="eln-btn-primary"><AppIcon name="plus" :size="14" />New location</button>
        <button class="eln-btn-ghost">New box</button>
        <button class="eln-btn-ghost">Find an item</button>
      </div>
      <div class="lc-tool-mid">
        <div class="lc-search">
          <AppIcon name="search" :size="14" />
          <input v-model="keyword" placeholder="搜索位置名称 / 编号 / 物品…" />
        </div>
        <button class="lc-check" :class="{ on: recursive }" @click="recursive = !recursive">
          <span class="lc-box" :class="{ on: recursive }">
            <AppIcon v-if="recursive" name="check" :size="11" />
          </span>
          Look inside locations（整棵子树检索）
        </button>
      </div>
      <div class="lc-tool-right">
        <button class="eln-btn-ghost">管理列</button>
      </div>
    </div>

    <!-- 表格 -->
    <div class="lc-card">
      <table class="eln-table">
        <thead>
          <tr>
            <th class="eln-th">Location name</th>
            <th class="eln-th" style="width:110px">ID</th>
            <th class="eln-th" style="width:110px">Sub-locations</th>
            <th class="eln-th" style="width:100px">存放物品数</th>
            <th class="eln-th" style="width:180px">关联项目/实验</th>
            <th class="eln-th" style="width:90px">Shared</th>
            <th class="eln-th" style="width:130px">Owned by</th>
            <th class="eln-th" style="width:110px">Created on</th>
            <th class="eln-th" style="width:100px">Created by</th>
            <th class="eln-th" style="width:40px"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in rows" :key="r.id">
            <td class="eln-td lc-strong">
              <span class="lc-name" @click="open(r)">
                {{ r.name }}
                <span class="lc-chev">▸</span>
              </span>
            </td>
            <td class="eln-td lc-mono">{{ r.id }}</td>
            <td class="eln-td" :class="{ 'lc-muted': r.sub === '/' }">{{ r.sub }}</td>
            <td class="eln-td lc-count">{{ r.items }}</td>
            <td class="eln-td">
              <span v-if="r.projects.length" class="lc-projects">{{ r.projects.join('、') }}</span>
              <span v-else class="lc-muted">—</span>
            </td>
            <td class="eln-td lc-muted">{{ r.shared }}</td>
            <td class="eln-td">{{ r.owner }}</td>
            <td class="eln-td">{{ r.createdOn }}</td>
            <td class="eln-td">{{ r.createdBy }}</td>
            <td class="eln-td lc-more">⋯</td>
          </tr>
          <tr v-if="rows.length === 0">
            <td class="eln-td lc-empty" colspan="10">当前层级下无匹配位置</td>
          </tr>
        </tbody>
      </table>
      <div class="lc-foot">
        共 {{ rows.length }} 项 · 行内操作 Edit / Move / Duplicate / Delete / Share（复制深拷贝整棵子树，含图片）；
        非容器行下钻子级列表、容器行进入盒子详情，「Sub-locations」列在容器行呈现占位「/」（SCN-ITEM-LOC-1/2）。
        逐角色：项目负责人／小组组长／组员不提供结构维护入口，列表上方出现 STATE-LOC-LOCK 只读锁定条，
        越权调用走 showNoPerm 不静默失败（REQ-LOC-AUDIT）。「Shared」列演示恒为「未共享」——跨团队共享为有意裁剪（DEC-016 决定 7①）。
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
const keyword = ref('')
const recursive = ref(false)

// 层级位置条（STATE-LOC-TREE-CRUMB）：根级为空串，逐级可回跳
const crumbPath = ref([])

// 演示树：仅复刻画布根级 3 行，子级为下钻行为的最小演示数据
const tree = {
  '': [
    { id: 'SL-L01', name: '上海研发中心', sub: '3', items: '47', projects: ['高温硅胶研究', 'PP 配方开发'], shared: '未共享', owner: '高分子材料组', createdOn: '2026-03-12', createdBy: '张伟' },
    { id: 'SL-A01', name: '化学品柜 A', sub: '2', items: '18', projects: ['高温硅胶研究'], shared: '未共享', owner: '高分子材料组', createdOn: '2026-03-14', createdBy: '李娜' },
    { id: 'SL-A02-1', name: '原料盒 A1', sub: '/', items: '9', projects: ['PP 配方开发'], shared: '未共享', owner: '高分子材料组', createdOn: '2026-04-02', createdBy: '王强', container: true }
  ],
  'SL-L01': [
    { id: 'SL-A01', name: '化学品柜 A', sub: '2', items: '18', projects: ['高温硅胶研究'], shared: '未共享', owner: '高分子材料组', createdOn: '2026-03-14', createdBy: '李娜' },
    { id: 'SL-B01', name: '化学品柜 B', sub: '1', items: '12', projects: ['高温硅胶研究'], shared: '未共享', owner: '高分子材料组', createdOn: '2026-03-14', createdBy: '李娜' },
    { id: 'SL-C01', name: '试剂冰箱 C', sub: '1', items: '17', projects: [], shared: '未共享', owner: '高分子材料组', createdOn: '2026-03-20', createdBy: '王强' }
  ],
  'SL-A01': [
    { id: 'SL-A02-1', name: '原料盒 A1', sub: '/', items: '9', projects: ['PP 配方开发'], shared: '未共享', owner: '高分子材料组', createdOn: '2026-04-02', createdBy: '王强', container: true },
    { id: 'SL-A02-2', name: '原料盒 A2', sub: '/', items: '9', projects: [], shared: '未共享', owner: '高分子材料组', createdOn: '2026-04-02', createdBy: '王强', container: true }
  ]
}

const currentPath = computed(() => crumbPath.value.map(c => c.id).join('/'))

const rows = computed(() => {
  const base = tree[currentPath.value] || []
  const k = keyword.value.trim().toLowerCase()
  if (!k) return base
  return base.filter(r => r.name.toLowerCase().includes(k) || r.id.toLowerCase().includes(k))
})

function open(r) {
  if (r.container) {
    router.push(`/locations/box/${r.id}`)
  } else {
    crumbPath.value = [...crumbPath.value, { id: r.id, name: r.name }]
  }
}

function goTo(i) {
  crumbPath.value = crumbPath.value.slice(0, i)
}
</script>

<style scoped>
.lc-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:559 内容区 gap 16 */
}
.breadcrumb {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  flex-wrap: wrap;
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
.lc-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.lc-head-note {
  max-width: 420px;
  padding-top: 4px;
  font-size: 12px;
  line-height: 1.6;
  text-align: right;
  color: var(--color-placeholder); /* 画布 79:567 权限提示 #A1A1AA */
}

/* 工具栏 */
.lc-toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.lc-tool-left {
  display: flex;
  gap: 8px;
}
.lc-tool-mid {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: 1;
  min-width: 320px;
}
.lc-tool-right {
  margin-left: auto;
}
.lc-search {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 36px;
  padding: 0 12px;
  min-width: 240px;
  flex: 1;
  max-width: 400px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  color: var(--color-text-secondary);
}
.lc-search input {
  flex: 1;
  border: none;
  outline: none;
  background: none;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
}
.lc-check {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  height: 36px;
  padding: 0 12px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  font-size: 13px;
  color: var(--color-subtle-text);
  white-space: nowrap;
}
.lc-check.on {
  border-color: var(--color-primary);
  color: var(--color-primary);
}
.lc-box {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 16px;
  height: 16px;
  border: 1px solid var(--color-border-strong);
  border-radius: 4px;
  color: #fff;
}
.lc-box.on {
  background: var(--color-primary);
  border-color: var(--color-primary);
}

/* 表格 */
.lc-card {
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  overflow: hidden;
}
.lc-strong {
  font-weight: 500;
}
.lc-mono {
  font-family: var(--font-en);
  color: var(--color-text-secondary);
}
.lc-muted {
  color: var(--color-placeholder);
}
.lc-more {
  color: var(--color-text-secondary);
  text-align: center;
}
.lc-name {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: var(--color-text);
  cursor: pointer;
}
.lc-name:hover {
  color: var(--color-primary);
}
.lc-chev {
  font-size: 11px;
  color: inherit;
}
.lc-count {
  font-weight: 500;
}
.lc-projects {
  color: var(--color-primary);
}
.lc-empty {
  text-align: center;
  color: var(--color-placeholder);
}
.lc-foot {
  padding: 12px 20px 16px;
  font-size: 11px;
  line-height: 1.8;
  color: var(--color-placeholder);
}
</style>
