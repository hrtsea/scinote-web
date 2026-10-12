<template>
  <!--
    个人行动工作台（/eln_workbench）—— ADR-0048：只显示需要处理的事。
    纵排三区（Q13=A，移动端天然友好）：待办事项 → 审批事项 → 进行中的项目。
    🔴 组件里没有任何写死的宿主路由 / 色值 / 业务名词：
       · 每条行动的跳转目标 to 由 payload 用宿主真实 path helper 下发；
       · 分组标签取该组首条的 type（业务命名留在服务端）；
       · 拿不到真数据就渲染空态，绝不回落 mock.js 的画布演示值。
  -->
  <div class="workbench">
    <PageHeader :title="meta.greeting" :subtitle="meta.updatedAt">
      <template #title-extra>
        <span class="eln-badge eln-badge-blue">{{ meta.role }}</span>
      </template>
    </PageHeader>

    <!-- 通知栏（可点铃铛 + 下拉）：点击铃铛展开通知列表，点通知跳转业务页。
         🔴 .stop 不可省：document 上挂了「点空白关闭下拉」的监听，
         少了 .stop 时点击事件会冒泡到 document → toggleNotif 刚把 showNotif 置 true，
         onDocClick 立刻又置回 false —— 下拉**永远打不开**。 -->
    <div class="notice-wrap">
      <button class="notice-bar" type="button" @click.stop="toggleNotif">
        <AppIcon name="bell" :size="16" />
        <span class="notice-text">{{ noticeText }}</span>
        <span v-if="notifUnread > 0" class="notif-badge">{{ notifUnread > 99 ? '99+' : notifUnread }}</span>
      </button>
      <div v-if="showNotif" class="notif-dropdown" @click.stop>
        <div class="notif-head">
          <span>通知</span>
          <span class="notif-unread-text">未读 {{ notifUnread }}</span>
        </div>
        <div v-if="notifItems.length" class="notif-list">
          <button
            v-for="n in notifItems"
            :key="n.id"
            class="notif-item"
            :class="{ unread: !n.read }"
            type="button"
            @click="openNotif(n)"
          >
            <div class="notif-title">{{ n.title }}</div>
            <div class="notif-msg">{{ n.message }}</div>
            <div class="notif-time num">{{ n.createdAt }}</div>
          </button>
        </div>
        <div v-else class="notif-empty">暂无通知</div>
      </div>
    </div>

    <!-- ========== 区一：待办事项（我的未完成任务 + 我的申请待验货） ========== -->
    <section class="panel-card">
      <div class="panel-head">
        <span class="panel-title">待办事项</span>
        <!-- 无跨项目任务清单页 ⇒ 不给「查看全部」（Q7=A 只接已有承载面），只报真实总数 -->
        <span class="panel-count num">共 {{ totals.todos }} 条</span>
      </div>
      <div v-if="todos.length" class="action-list">
        <component
          :is="actionTag(t)"
          v-for="(t, i) in todos"
          :key="`${t.kind}-${t.title}-${i}`"
          v-bind="actionBind(t)"
          class="action-item"
          :class="{ clickable: !!t.to, overdue: t.overdue }"
        >
          <span class="action-type">{{ t.type }}</span>
          <span class="action-title" :title="t.title">{{ t.title }}</span>
          <span class="action-due num" :class="{ 'due-overdue': t.overdue }">{{ t.due }}</span>
          <span class="action-status" :class="t.tone">{{ t.status }}</span>
        </component>
      </div>
      <div v-else class="zone-empty">暂无待办事项</div>
    </section>

    <!-- ========== 区二：审批事项（待我审：资源申请 / 任务关闭 / 到货验收） ========== -->
    <section class="panel-card">
      <div class="panel-head">
        <span class="panel-title">审批事项</span>
        <span class="panel-count num">共 {{ totals.approvals }} 条</span>
      </div>
      <template v-for="grp in approvalGroups" :key="grp.kind">
        <div class="group-head">
          <span class="group-name">{{ grp.type }}</span>
          <span class="group-count num">{{ grp.items.length }} 条</span>
          <!-- 只有资源申请段有跨项目承载面（资源中心申请单 tab）⇒ 只它给「查看全部」 -->
          <router-link
            v-if="grp.kind === 'resource_application' && links.resourceApplicationsAll"
            class="panel-link"
            :to="links.resourceApplicationsAll"
          >查看全部</router-link>
        </div>
        <div class="action-list">
          <component
            :is="actionTag(t)"
            v-for="(t, i) in grp.items"
            :key="`${t.kind}-${t.title}-${i}`"
            v-bind="actionBind(t)"
            class="action-item"
            :class="{ clickable: !!t.to }"
          >
            <span class="action-type">{{ t.type }}</span>
            <span class="action-title" :title="t.title">{{ t.title }}</span>
            <span class="action-due num">{{ t.due }}</span>
            <span class="action-status" :class="t.tone">{{ t.status }}</span>
          </component>
        </div>
      </template>
      <div v-if="!approvals.length" class="zone-empty">暂无待审批事项</div>
    </section>

    <!-- ========== 区三：进行中的项目（参与 ∩ 活动，与项目列表页同一真源） ========== -->
    <section class="panel-card">
      <div class="panel-head">
        <span class="panel-title">进行中的项目</span>
        <router-link v-if="links.projectsAll" class="panel-link" :to="links.projectsAll">查看全部</router-link>
      </div>
      <div v-if="projects.length" class="action-list">
        <component
          :is="actionTag(p)"
          v-for="(p, i) in projects"
          :key="`project-${p.name}-${i}`"
          v-bind="actionBind(p)"
          class="action-item project-item"
          :class="{ clickable: !!p.to }"
        >
          <span class="project-name" :title="p.name">{{ p.name }}</span>
          <span class="project-status" :class="p.status">{{ p.statusLabel }}</span>
          <span class="project-role" :class="{ responsible: p.role === '负责' }">{{ p.role }}</span>
          <span v-if="p.taskSummary" class="project-tasks num">{{ p.taskSummary }}</span>
        </component>
      </div>
      <div v-else class="zone-empty">暂无进行中的项目</div>
    </section>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue/dist/vue.esm-bundler.js'
import PageHeader from '../components/PageHeader.vue'
import AppIcon from '../components/AppIcon.vue'
import { workbenchPayload } from '../data/mock'

// ★ 六块全部只读注入容器（真机由 eln_ui 的 WorkbenchPayload 实时下发，
//   原型独立跑用 mock.js 里的画布演示默认值兜底）。组件里不再有任何写死的
//   宿主路由 / 色值 / 演示文案 —— 拿不到真数据就渲染空态，绝不回落演示值。
const meta = workbenchPayload.meta
const todos = workbenchPayload.todos
const approvals = workbenchPayload.approvals
const projects = workbenchPayload.projects
const links = workbenchPayload.links || {}
const totals = workbenchPayload.totals || { todos: 0, approvals: 0, projects: 0 }

// ------------------------------------------------------------
// 行动项渲染（与旧版 KPI 卡同一套「有 to 才可点」纪律，Q11=A）：
//   有 to → router-link（整页跳转，宿主路由由 payload 下发）
//   无 to → div（原生无承载面 → 显式留白，不做「可点但没反应」的假入口）
// ⚠ `is` 与其余 attrs 分开给：`<component>` 的动态类型只认 `:is`。
// ------------------------------------------------------------
function actionTag(item) {
  return item.to ? 'router-link' : 'div'
}

function actionBind(item) {
  return item.to ? { to: item.to } : {}
}

// 审批事项按 kind 分小段（Q8=A）。段序固定（资源申请 → 任务关闭 → 到货验收），
// 与 payload 输出序一致；段名取该段首条的 type（业务命名不硬编在组件里）。
const APPROVAL_GROUP_ORDER = ['resource_application', 'task_close', 'receipt']
const approvalGroups = computed(() => {
  const byKind = {}
  approvals.forEach((a) => {
    if (!a || !a.kind) return
    ;(byKind[a.kind] = byKind[a.kind] || []).push(a)
  })
  return APPROVAL_GROUP_ORDER.filter((k) => byKind[k]?.length).map((k) => ({
    kind: k,
    type: byKind[k][0].type,
    items: byKind[k]
  }))
})

// ------------------------------------------------------------
// 通知中心：铃铛读真机 /eln_notifications，点开下拉、点通知跳转业务页并标记已读。
// 失败静默（保 meta.notice 兜底文案）。
// ------------------------------------------------------------
const notifItems = ref([])
const notifUnread = ref(0)
const showNotif = ref(false)
const noticeText = computed(() =>
  notifUnread.value > 0 ? `您有 ${notifUnread.value} 条未读通知` : (meta.notice || '暂无未读通知')
)

async function loadNotif() {
  try {
    const res = await fetch('/eln_notifications', {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin'
    })
    if (!res.ok) return
    const data = await res.json()
    notifItems.value = data.items || []
    notifUnread.value = data.unread || 0
  } catch {
    /* 静默：保持静态文案兜底 */
  }
}

function toggleNotif() {
  showNotif.value = !showNotif.value
}

async function openNotif(n) {
  if (!n.read) {
    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')
      await fetch(`/eln_notifications/${n.id}/read`, {
        method: 'PATCH',
        headers: { ...(csrf ? { 'X-CSRF-Token': csrf.content } : {}) },
        credentials: 'same-origin'
      })
    } catch {
      /* 标记已读失败不影响跳转 */
    }
    n.read = true
    notifUnread.value = Math.max(0, notifUnread.value - 1)
  }
  showNotif.value = false
  if (n.url) window.location.href = n.url
}

function onDocClick() {
  showNotif.value = false
}
onMounted(() => {
  loadNotif()
  document.addEventListener('click', onDocClick)
})
onBeforeUnmount(() => document.removeEventListener('click', onDocClick))
</script>

<style scoped>
.workbench {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 18px;
}

/* 通知栏（可点铃铛 + 下拉） */
.notice-wrap {
  position: relative;
}
.notice-bar {
  width: 100%;
  height: 44px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 14px;
  background: var(--color-notice-bg);
  border: none;
  border-radius: 10px;
  font-family: inherit;
  font-size: 13px;
  color: var(--color-notice-text);
  text-align: left;
  cursor: pointer;
  transition: background 0.15s ease;
}
.notice-bar:hover {
  background: #FED7AA;
}
.notice-bar svg {
  flex-shrink: 0;
}
.notice-text {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.notif-badge {
  flex-shrink: 0;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 9px;
  background: #EF4444;
  color: #fff;
  font-size: 11px;
  font-weight: 600;
  font-family: var(--font-en);
}
.notif-dropdown {
  position: absolute;
  top: 52px;
  right: 0;
  width: 340px;
  max-height: 420px;
  overflow-y: auto;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 12px;
  box-shadow: var(--shadow-card);
  z-index: 50;
  display: flex;
  flex-direction: column;
}
.notif-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 14px;
  border-bottom: 1px solid var(--color-border);
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
}
.notif-unread-text {
  font-size: 11px;
  font-weight: 400;
  color: var(--color-placeholder);
}
.notif-list {
  display: flex;
  flex-direction: column;
}
.notif-item {
  display: flex;
  flex-direction: column;
  gap: 3px;
  padding: 10px 14px;
  background: none;
  border: none;
  border-bottom: 1px solid var(--color-border);
  text-align: left;
  cursor: pointer;
  font-family: inherit;
}
.notif-item:last-child {
  border-bottom: none;
}
.notif-item:hover {
  background: #FAFAFA;
}
.notif-item.unread {
  background: #FFF7ED;
}
.notif-item.unread:hover {
  background: #FFEDD5;
}
.notif-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.4;
}
.notif-msg {
  font-size: 12px;
  color: var(--color-text-secondary);
  line-height: 1.5;
}
.notif-time {
  font-size: 11px;
  color: var(--color-placeholder);
}
.notif-empty {
  padding: 24px 14px;
  text-align: center;
  font-size: 12px;
  color: var(--color-placeholder);
}

/* 三区卡片（统一纵排，Q13=A） */
.panel-card {
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.panel-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}
.panel-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
}
.panel-count {
  font-size: 12px;
  color: var(--color-placeholder);
}
.panel-link {
  border: none;
  background: transparent;
  font-size: 12px;
  color: var(--color-primary);
  padding: 0;
  text-decoration: none;
}
.panel-link:hover {
  text-decoration: underline;
}
.zone-empty {
  padding: 28px 0;
  text-align: center;
  font-size: 13px;
  color: var(--color-placeholder);
}

/* 审批事项的来源小段头 */
.group-head {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 2px;
}
.group-name {
  font-size: 12px;
  font-weight: 600;
  color: var(--color-text-secondary);
}
.group-count {
  font-size: 11px;
  color: var(--color-placeholder);
}
.group-head .panel-link {
  margin-left: auto;
}

/* 行动项（待办 / 审批共用同一形状：类型标签 + 标题 + 截止 + 状态） */
.action-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.action-item {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 46px;
  padding: 8px 10px;
  background: #FAFAFA;
  border-radius: 8px;
  text-decoration: none;
  color: inherit;
}
.action-item.clickable {
  cursor: pointer;
  transition: background 0.15s ease, border-color 0.15s ease;
}
.action-item.clickable:hover {
  background: var(--color-active-bg, #EFF6FF);
}
.action-item.clickable:focus-visible {
  outline: 2px solid var(--color-primary);
  outline-offset: 2px;
}
.action-item.overdue {
  background: #FEF2F2;
}
.action-type {
  padding: 5px;
  background: var(--color-fill-soft);
  border-radius: 5px;
  font-size: 11px;
  font-weight: 500;
  color: var(--color-subtle-text);
  flex-shrink: 0;
}
.action-title {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  color: var(--color-text-menu);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.action-due {
  font-size: 12px;
  color: var(--color-text-secondary);
  flex-shrink: 0;
}
.action-due.due-overdue {
  color: #EF4444;
  font-weight: 600;
}
.action-status {
  font-size: 12px;
  font-weight: 500;
  flex-shrink: 0;
}
.action-status.warn {
  color: #F59E0B;
}
.action-status.danger {
  color: #EF4444;
}
.action-status.purple {
  color: #7C3AED;
}
.action-status.primary {
  color: var(--color-primary);
}

/* 项目项（名称 + 三态徽标 + 角色 + 任务摘要） */
.project-item {
  align-items: center;
}
.project-name {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text-menu);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.project-status {
  flex-shrink: 0;
  padding: 3px 8px;
  border-radius: 10px;
  font-size: 11px;
  font-weight: 500;
  background: var(--color-fill-soft);
  color: var(--color-subtle-text);
}
.project-status.active {
  background: #EFF6FF;
  color: var(--color-primary);
}
.project-status.done {
  background: #ECFDF5;
  color: #10B981;
}
.project-role {
  flex-shrink: 0;
  width: 34px;
  font-size: 12px;
  color: var(--color-subtle-text);
}
.project-role.responsible {
  color: var(--color-primary);
  font-weight: 600;
}
.project-tasks {
  flex-shrink: 0;
  font-size: 11px;
  color: var(--color-placeholder);
}

/* 移动端：收窄内边距，行动项允许换行不至于挤成一团 */
@media (max-width: 640px) {
  .workbench {
    padding: 14px;
    gap: 14px;
  }
  .panel-card {
    padding: 14px;
  }
  .action-item {
    flex-wrap: wrap;
  }
  .action-title {
    flex-basis: 100%;
    order: -1;
    white-space: normal;
  }
}
</style>
