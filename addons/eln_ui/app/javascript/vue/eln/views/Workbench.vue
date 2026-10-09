<template>
  <!-- 工作台（画布 4:66 / 4:118）：页头 + 通知栏 + KPI 4 卡 + 左主列 + 右列 340 -->
  <div class="workbench">
    <PageHeader :title="meta.greeting" :subtitle="meta.updatedAt">
      <template #title-extra>
        <span class="eln-badge eln-badge-blue">{{ meta.role }}</span>
      </template>
    </PageHeader>

    <!-- 通知栏（4:125 高44 #FFF7ED 圆角10）：点击铃铛展开通知列表，点通知跳转业务页 -->
    <!-- 🔴 .stop 不可省：document 上挂了「点空白关闭下拉」的监听，
         少了 .stop 时点击事件会冒泡到 document → toggleNotif 刚把 showNotif 置 true，
         onDocClick 立刻又置回 false —— 下拉**永远打不开**（用户报的
         「通知只有提示无法下钻查看」就是这个）。 -->
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
        <!-- ⚠ 这里**故意没有**「查看全部」链接：/eln_notifications 是纯 JSON 端点
             （notifications_controller#index 只 render json），宿主没有通知中心
             页面。按 Q1-A「只接已存在的承载面」——不编一个点进去 404 的入口。
             下拉列表本身 + 每条点开跳业务页，就是本轮的「能下钻」。
             待办：若要「通知中心页」需另立 issue（新路由 + 新页面）。 -->
      </div>
    </div>

    <!-- 指标卡组（4:128 高108 白底 圆角12 pad16）
         🔴 V1.25：卡片可下钻。目标由 **payload 下发**（spec SCN-DASH-8）：
           · k.to     → 宿主真实路由（渲染成 router-link，整页跳转）
           · k.anchor → 本页内某张卡的 DOM id（渲染成 <a href="#id">，平滑滚动）
           两者都没有 → 保持普通 div（原生无承载面 = 显式留白，不做假入口）。
         组件里**不判断路由是否存在**，也不再硬编任何宿主路径。 -->
    <div class="kpi-grid">
      <component
        v-for="k in workbenchKpis"
        :key="k.label"
        :is="kpiTag(k)"
        v-bind="kpiBind(k)"
        class="kpi-card"
        :class="{ clickable: !!(k.to || k.anchor) }"
        @click="onKpiClick(k, $event)"
      >
        <div class="kpi-label">{{ k.label }}</div>
        <div class="kpi-value">{{ k.value }}</div>
        <div class="kpi-trend" :class="{ warn: k.tone === 'warn' }">{{ k.trend }}</div>
      </component>
    </div>

    <!-- 主内容区（4:216 左列 fill + 右列 340） -->
    <div class="wb-cols">
      <div class="wb-left">
        <!-- 卡片-个人待办（4:219） -->
        <section class="panel-card">
          <div class="panel-head">
            <span class="panel-title">个人待办</span>
            <button class="panel-link">查看全部</button>
          </div>
          <div class="todo-list">
            <div v-for="t in workbenchTodos" :key="t.title" class="todo-item">
              <span class="todo-type">{{ t.type }}</span>
              <span class="todo-title">{{ t.title }}</span>
              <span class="todo-due num">{{ t.due }}</span>
              <span class="todo-status" :class="t.tone">{{ t.status }}</span>
            </div>
          </div>
        </section>

        <!-- 卡片-任务状态分布（4:241：卡 gap14 / 条形图区 h210 gap24） -->
        <section class="panel-card g14">
          <div class="panel-head col">
            <span class="panel-title">任务状态分布</span>
            <!-- 状态机真名由 payload 下发（真机是数据库的 MyModuleStatus 名） -->
            <span class="panel-sub">状态机：{{ meta.statusMachine }}</span>
          </div>
          <div class="bar-chart">
            <div v-for="d in workbenchDist" :key="d.label" class="bar-row">
              <span class="bar-label">{{ d.label }}</span>
              <span class="bar-track">
                <span
                  class="bar-fill"
                  :style="{ width: barWidth(d.num) + 'px', background: d.color }"
                ></span>
              </span>
              <span class="bar-num num">{{ d.num }}</span>
            </div>
          </div>
        </section>
      </div>

      <div class="wb-right">
        <!-- 卡片-小组汇总（4:261：卡 gap10 / 表头与数据行均无左右内缩）
             🔴 V1.25：本卡是「小组数」KPI 的**页内下钻目标**（Q2 裁决 / SCN-DASH-8）。
                id 直接取 payload 下发的 anchor（服务端知道、前端不猜）；
                payload 没给就不渲染 id，KPI 卡也就不会被渲染成可点。 -->
        <section class="panel-card g10" :id="groupsAnchorId || undefined">
          <div class="panel-head">
            <span class="panel-title">小组汇总</span>
            <button class="panel-link">下钻小组</button>
          </div>
          <div class="group-head">
            <span class="gh-name">小组</span>
            <span class="gh-leader">组长</span>
            <span class="gh-rate">任务完成率</span>
          </div>
          <div v-for="g in workbenchGroups" :key="g.name" class="group-row">
            <span class="gr-name">{{ g.name }}</span>
            <span class="gr-leader">{{ g.leader }}</span>
            <span class="gr-rate num" :class="g.tone">{{ g.rate }}</span>
          </div>
        </section>

        <!-- 卡片-快捷入口（4:293） -->
        <section class="panel-card">
          <div class="panel-head">
            <span class="panel-title">快捷入口</span>
          </div>
          <div class="quick-entries">
            <router-link v-for="e in workbenchEntries" :key="e.label" :to="e.to" class="entry">
              {{ e.label }}
            </router-link>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue/dist/vue.esm-bundler.js'
import PageHeader from '../components/PageHeader.vue'
import AppIcon from '../components/AppIcon.vue'
import { workbenchPayload } from '../data/mock'

// ★ 六块全部只读注入容器（真机由 addons/workbench 实时下发，原型独立跑用
//   mock.js 里的画布演示默认值兜底）。组件里不再有任何写死的宿主路由、
//   色值、演示文案 —— 拿不到真数据就渲染空态，绝不回落演示值。
const meta = workbenchPayload.meta
const workbenchKpis = workbenchPayload.kpis
const workbenchTodos = workbenchPayload.todos
const workbenchDist = workbenchPayload.dist
const workbenchGroups = workbenchPayload.groups
const workbenchEntries = workbenchPayload.entries

// 通知中心（REQ-NOTIF / SCN-DASH-7）：铃铛读真机 /eln_notifications，
// 点开下拉、点通知跳转业务页并标记已读。失败静默（保原型静态 meta.notice 兜底）。
const notifItems = ref([])
const notifUnread = ref(0)
const showNotif = ref(false)
const noticeText = computed(() =>
  notifUnread.value > 0 ? `您有 ${notifUnread.value} 条未读通知` : (meta.notice || '暂无未读通知')
)

// ------------------------------------------------------------
// KPI 下钻（V1.25 / SCN-DASH-8）
//   🔴 前端**不判断**目标是否存在、不硬编任何宿主路径 —— 一律读 payload：
//     k.to     = 宿主真实路由（后端用 path helper 生成）
//     k.anchor = 本页内目标卡的 DOM id（后端下发，避免前后端各写一份 id 而漂）
//   这是「前端不写死宿主路由」铁律在**页内锚点**上的同一套做法。
// ------------------------------------------------------------

// 「小组数」锚点目标的 id：从 payload 的 anchor 字段取；取不到就不渲染 id。
const groupsAnchorId = computed(() => workbenchKpis.find((k) => k.anchor)?.anchor || '')

// 把一张 KPI 卡映射成合适的元素：
//   有 to     → router-link（整页跳转，宿主路由）
//   有 anchor → <a href="#id">（页内锚点，天然可键盘访问/可右键复制）
//   都没有    → div（原生无承载面 → 显式留白，不是「可点但没反应」）
// ⚠ `is` 与其余 attrs 分开给：`<component>` 的动态类型只认 `:is`，
//   把 is 混进 v-bind 对象里依赖内部合并顺序，不写成隐式行为。
function kpiTag(k) {
  if (k.to) return 'router-link'
  if (k.anchor) return 'a'
  return 'div'
}

function kpiBind(k) {
  if (k.to) return { to: k.to }
  if (k.anchor) return { href: `#${k.anchor}` }
  return {}
}

function onKpiClick(k, ev) {
  if (!k.anchor) return // 有 to 的交给 router-link 自己跳
  ev.preventDefault()
  document.getElementById(k.anchor)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

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
    /* 静默：保持原型静态文案兜底 */
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

// 画布 4:247~4:260：条形宽度按最大值归一（最大条 = 506.35px）
const BAR_MAX = 506.35
function barWidth(n) {
  const max = Math.max(...workbenchDist.map((d) => d.num))
  return Math.round((n / max) * BAR_MAX * 100) / 100
}
</script>

<style scoped>
.workbench {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 18px;
}

/* 通知栏 4:125（现为可点铃铛 + 下拉） */
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

/* KPI 4:200 起 */
.kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
}
.kpi-card {
  height: 108px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.kpi-label {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.kpi-value {
  font-family: var(--font-en);
  font-size: 28px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.1;
}
.kpi-trend {
  font-size: 11px;
  color: var(--color-text-secondary);
}
.kpi-trend.warn {
  color: #F59E0B;
}

/* V1.25：可下钻的卡会被渲染成 router-link / <a> —— 去掉链接默认样式并给 hover 反馈。
   不可下钻的卡仍是普通 div（不显示 pointer，不给「能点」的错觉）。 */
.kpi-card.clickable {
  cursor: pointer;
  text-decoration: none;
  color: inherit;
  transition: border-color 0.15s ease, box-shadow 0.15s ease, transform 0.1s ease;
}
.kpi-card.clickable:hover {
  border-color: var(--color-primary);
  box-shadow: 0 2px 10px rgba(48, 112, 237, 0.14);
}
.kpi-card.clickable:focus-visible {
  outline: 2px solid var(--color-primary);
  outline-offset: 2px;
}
.kpi-card.clickable:active {
  transform: translateY(1px);
}

/* 双列 */
.wb-cols {
  display: flex;
  gap: 16px;
  align-items: flex-start;
}
.wb-left {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.wb-right {
  width: 340px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

/* 卡片内间距按卡不同：4:219 个人待办 / 4:293 快捷入口 = gap12；
   4:241 任务状态分布 = gap14；4:261 小组汇总 = gap10。
   统一由卡 gap 控制（卡头不再用 margin-bottom）。 */
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
.panel-card.g14 {
  gap: 14px;
}
.panel-card.g10 {
  gap: 10px;
}
.panel-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}
/* 画布 4:242：卡头为**横向**——「任务状态分布」+ 状态机说明并排（gap10 / 垂直居中），说明 fill 占满剩余宽 */
.panel-head.col {
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
  gap: 10px;
}
.panel-head.col .panel-sub {
  flex: 1;
  min-width: 0;
}
.panel-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
}
.panel-sub {
  font-size: 11px;
  color: var(--color-placeholder);
}
.panel-link {
  border: none;
  background: transparent;
  font-size: 12px;
  color: var(--color-primary);
  padding: 0;
}

/* 个人待办 4:223 高46 #FAFAFA r8 */
.todo-list {
  display: flex;
  flex-direction: column;
  gap: 12px; /* 画布 4:219 卡 gap12（待办项 4:223/4:229/4:235 为卡直属子项） */
}
.todo-item {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 46px;
  padding: 0 10px;
  background: #FAFAFA;
  border-radius: 8px;
}
.todo-type {
  padding: 5px;
  background: var(--color-fill-soft);
  border-radius: 5px;
  font-size: 11px;
  font-weight: 500;
  color: var(--color-subtle-text);
  flex-shrink: 0;
}
.todo-title {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  color: var(--color-text-menu);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.todo-due {
  font-size: 12px;
  color: var(--color-text-secondary);
  flex-shrink: 0;
}
.todo-status {
  font-size: 12px;
  font-weight: 500;
  flex-shrink: 0;
}
.todo-status.warn {
  color: #F59E0B;
}
.todo-status.purple {
  color: #7C3AED;
}
.todo-status.primary {
  color: var(--color-primary);
}

/* 任务状态分布 4:245 */
/* 画布 4:245（layout:none / h210）：条顶 y = 10/50/90/130/170，条高 16 → **行距 40**（gap 24）；
   末条底 186，到底边再留 24 → padding 10px 0 24px */
.bar-chart {
  display: flex;
  flex-direction: column;
  gap: 24px;
  padding: 10px 0 24px;
}
.bar-row {
  display: flex;
  align-items: center;
  gap: 8px; /* 画布：条起点固定 110.733（标签列 103 + 8）；条尾到数值同为 8 */
}
.bar-label {
  width: 103px;
  flex-shrink: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.bar-track {
  display: block;
  flex-shrink: 0;
}
.bar-fill {
  display: block;
  height: 16px;
  border-radius: 0;
}
.bar-num {
  font-size: 12px;
  color: var(--color-text-menu);
}

/* 小组汇总 4:265 */
/* 画布 4:265（表头）/ 4:272 起（数据行）：**均无左右内缩**（padding 0），
   文字起点即卡片 20px 内边距处；表头底 #F5F5F7 / r6 / h40。 */
.group-head {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 40px;
  padding: 0;
  background: var(--color-table-header);
  border-radius: var(--radius-table-header);
}
.group-head span {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-text-secondary);
}
.gh-name,
.gr-name {
  flex: 1;
  min-width: 0;
}
.gh-leader,
.gr-leader {
  width: 80px;
  flex-shrink: 0;
}
.gh-rate,
.gr-rate {
  width: 72px;
  flex-shrink: 0;
}
.group-row {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 40px;
  padding: 0;
}
.gr-name {
  font-size: 13px;
  color: var(--color-text-menu);
}
.gr-leader {
  font-size: 13px;
  color: var(--color-subtle-text);
}
.gr-rate {
  font-size: 13px;
  font-weight: 600;
}
.gr-rate.done {
  color: #10B981;
}
.gr-rate.warn {
  color: #F59E0B;
}

/* 快捷入口 4:296 146x44 #F4F4F5 r8 */
.quick-entries {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.entry {
  display: flex;
  align-items: center;
  justify-content: center;
  /* 画布 4:296 为固定 146px；卡内容宽恰为 300（=146×2+8），固定宽在边界上会因亚像素误差掉行，
     故用 calc 表达同一几何（300 容器下 = 146）。 */
  width: calc(50% - 4px);
  height: 44px;
  background: var(--color-fill-soft);
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text-menu);
  text-decoration: none;
  transition: background 0.15s ease, color 0.15s ease;
}
.entry:hover {
  background: var(--color-active-bg);
  color: var(--color-primary);
}
</style>
