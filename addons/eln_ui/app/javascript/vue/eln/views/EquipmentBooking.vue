<template>
  <!-- 设备预定（画布 70:12 日 / 70:203 周 / 70:418 月）：左设备列表 300 + 右占用日历 + 新建预定 -->
  <div class="equip-booking">
    <!-- 面包屑 70:16 -->
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/eln_res_center" class="crumb-link">资源中心</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">设备预定</span>
    </div>

    <!-- 页头 70:17（标题组 gap 6 / 操作组 gap 8，按钮 36 高且**无图标**） -->
    <div class="eb-head">
      <PageHeader
        title="设备预定"
        subtitle="资源中心 · 按设备查看当日占用，选中时段提交预定申请，设备负责人审批后生效（DEC-011）"
      />
      <div class="eb-head-actions">
        <button class="eln-btn-ghost" @click="scrollTo(calCardRef)">我的预定</button>
        <button class="eln-btn-primary" @click="scrollTo(formCardRef)">新建预定</button>
      </div>
    </div>

    <!-- 主区 70:27（gap 16） -->
    <div class="eb-main">
      <!-- 左：卡片-设备列表 70:28（pad16 / gap12 / r12 / w300） -->
      <aside class="dev-card">
        <!-- 卡头 70:29：标题「设备列表」+ 计数 chip 70:31（h20 / pad 0 8 / r10 / #F0F6FF） -->
        <div class="dev-head">
          <span class="dev-head-title">设备列表</span>
          <span class="dev-count">{{ devices.length }} 台</span>
        </div>

        <!-- 搜索框 70:33（h36 / pad 0 10 / gap6 / r8） -->
        <div class="dev-search">
          <AppIcon name="search" :size="14" />
          <input v-model="deviceKeyword" placeholder="搜索设备名称 / 型号" />
        </div>

        <!-- 设备列表 70:35（gap 4，无内边距；行 70:36 h53 = pad 8 + 36 图标） -->
        <div class="dev-list">
          <button
            v-for="d in filteredDevices"
            :key="d.id"
            class="dev-item"
            :class="{ active: selectedDeviceId === d.id }"
            @click="selectDevice(d.id)"
          >
            <span class="dev-thumb">{{ d.icon }}</span>
            <span class="dev-meta">
              <span class="dev-name">{{ d.name }}</span>
              <span class="dev-model">{{ d.code }} · {{ d.spec }}</span>
            </span>
            <span class="dev-status" :style="statusStyle(d.status)">
              {{ deviceStatusText[d.status] }}
            </span>
          </button>
          <p v-if="filteredDevices.length === 0" class="dev-empty">未找到匹配设备</p>
        </div>

        <!-- 底注 70:76（pad 0 2 / 11px #A1A1AA） -->
        <p class="dev-note">设备采用负责人审批制，提交后由设备负责人确认时段</p>
      </aside>

      <!-- 右栏 70:78（gap 16） -->
      <div class="eb-right">
        <!-- 卡片-占用日历 70:79（pad 20 / gap 14） -->
        <section class="cal-card" ref="calCardRef">
          <!-- 卡头 70:80：标题 + 控制组 70:82（日期步进 70:83 + 视图切换 70:87，gap 8） -->
          <div class="cal-head">
            <div class="cal-title">占用日历</div>
            <div class="cal-tools">
              <div class="date-step">
                <button class="step-btn" title="上一时段" @click="step(-1)">‹</button>
                <span class="step-label">{{ navLabel }}</span>
                <button class="step-btn" title="下一时段" @click="step(1)">›</button>
              </div>
              <div class="seg">
                <button class="seg-btn" :class="{ active: viewMode === 'day' }" @click="viewMode = 'day'">日</button>
                <button class="seg-btn" :class="{ active: viewMode === 'week' }" @click="viewMode = 'week'">周</button>
                <button class="seg-btn" :class="{ active: viewMode === 'month' }" @click="viewMode = 'month'">月</button>
              </div>
            </div>
          </div>

          <!-- 当前设备条 70:198（h36 / pad 12px 8px / r8 / #F0F6FF / gap 8） -->
          <div class="cal-current">
            <span class="cc-name">当前查看：{{ selectedDevice.name }} · {{ selectedDevice.code }}</span>
            <span class="cc-status" :style="statusStyle(selectedDevice.status)">
              {{ deviceStatusText[selectedDevice.status] }}
            </span>
            <span class="cc-hint">切换设备请点左侧列表 · 负责人 {{ selectedDevice.owner }}</span>
          </div>

          <!-- 周视图上/下滚动提示 70:839 / 70:846（pad-left 44 / 11px #C4C4CC） -->
          <div v-if="viewMode === 'week'" class="cal-scroll-hint">00:00 – 08:00 向上滚动查看</div>

          <div class="cal-body">
            <DayView
              v-if="viewMode === 'day'"
              :device="selectedDevice"
              :date="currentDate"
              :events="dayEvents"
            />
            <WeekView
              v-else-if="viewMode === 'week'"
              :days="weekDays"
              :events-by-day="weekEventsByDay"
            />
            <MonthView
              v-else
              :matrix="monthMatrix"
              :events-map="monthEventsMap"
              :focus-month="monthFocus"
            />
          </div>

          <div v-if="viewMode === 'week'" class="cal-scroll-hint">20:00 – 24:00 向下滚动查看</div>

          <!-- 图例 70:148（gap 16 / pad-left 162，与日列左缘对齐） -->
          <div class="cal-legend">
            <span v-for="t in legendTypes" :key="t" class="lg-item">
              <span class="lg-dot" :style="{ background: bookingTypeStyle[t].bg }"></span>
              {{ bookingTypeStyle[t].label }}
            </span>
          </div>
        </section>

        <!-- 卡片-新建预定 70:161（pad 20 / gap 14） -->
        <section class="form-card" ref="formCardRef">
          <!-- 卡头 70:162：标题 + 选中设备副题（gap 10） -->
          <div class="form-head">
            <span class="form-title">新建预定</span>
            <span class="form-sub">
              选中设备：{{ selectedDevice.name }} {{ selectedDevice.code }} · 设备负责人 {{ selectedDevice.owner }}
            </span>
          </div>
          <BookingForm @submit="onSubmit" />
        </section>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import { useRoute } from 'vue-router'
import AppIcon from '../components/AppIcon.vue'
import PageHeader from '../components/PageHeader.vue'
import DayView from '../components/booking/DayView.vue'
import WeekView from '../components/booking/WeekView.vue'
import MonthView from '../components/booking/MonthView.vue'
import BookingForm from '../components/booking/BookingForm.vue'
import {
  devices, deviceStatusText, deviceStatusStyle, bookingTypeStyle,
  bookings as seedBookings, TODAY, WEEKDAY_CN,
  getWeekDays, getMonthMatrix, ymd, addDays, makeBooking
} from '../data/equipment.js'

const selectedDeviceId = ref('UTM-500')
// 日 / 周 / 月三态（画布 70:12 / 70:203 / 70:418）；?view=week 可直链到指定态
const route = useRoute()
const viewMode = ref(['day', 'week', 'month'].includes(route.query.view) ? route.query.view : 'day')
const currentDate = ref(new Date(TODAY))
const deviceKeyword = ref('')
// 响应式预约表（演示提交可追加）
const bookings = ref(seedBookings.map((b) => ({ ...b })))

// 图例顺序对齐画布 70:149 / 70:155 / 72:5
const legendTypes = ['occupied', 'mine', 'maintenance']

const selectedDevice = computed(() => devices.find((d) => d.id === selectedDeviceId.value) || devices[0])

const filteredDevices = computed(() => {
  const kw = deviceKeyword.value.trim()
  if (!kw) return devices
  return devices.filter((d) => d.name.includes(kw) || d.code.includes(kw) || d.spec.includes(kw))
})

function statusStyle(s) {
  return deviceStatusStyle[s] || deviceStatusStyle.idle
}

function selectDevice(id) {
  selectedDeviceId.value = id
}

// ---- 各视图派生数据 ----
const dayEvents = computed(() =>
  bookings.value.filter((b) => b.deviceId === selectedDeviceId.value && b.date === ymd(currentDate.value))
)

const weekDays = computed(() => getWeekDays(currentDate.value))
const weekEventsByDay = computed(() =>
  weekDays.value.map((d) => bookings.value.filter((b) => b.deviceId === selectedDeviceId.value && b.date === ymd(d)))
)

const monthMatrix = computed(() => getMonthMatrix(currentDate.value))
const monthFocus = computed(() => currentDate.value.getMonth())
const monthEventsMap = computed(() => {
  const map = {}
  for (const b of bookings.value) {
    if (b.deviceId !== selectedDeviceId.value) continue
    ;(map[b.date] = map[b.date] || []).push(b)
  }
  for (const k in map) map[k].sort((a, b) => a.start.localeCompare(b.start))
  return map
})

// 卡头日期步进文案（画布 70:85「9月29日 · 周二」）
const navLabel = computed(() => {
  const d = currentDate.value
  if (viewMode.value === 'day') {
    const wd = WEEKDAY_CN[(d.getDay() + 6) % 7]
    return `${d.getMonth() + 1}月${d.getDate()}日 · 周${wd}`
  }
  if (viewMode.value === 'week') {
    const s = weekDays.value[0]
    const e = weekDays.value[6]
    return `${s.getMonth() + 1}月${s.getDate()}日 ~ ${e.getMonth() + 1}月${e.getDate()}日`
  }
  return `${d.getFullYear()}年${d.getMonth() + 1}月`
})

// ---- 导航 ----
function step(dir) {
  if (viewMode.value === 'day') {
    currentDate.value = addDays(currentDate.value, dir)
  } else if (viewMode.value === 'week') {
    currentDate.value = addDays(currentDate.value, dir * 7)
  } else {
    currentDate.value = new Date(currentDate.value.getFullYear(), currentDate.value.getMonth() + dir, 1)
  }
}

// ---- 提交新预定 ----
function onSubmit(payload) {
  const b = makeBooking({ ...payload, deviceId: selectedDeviceId.value })
  bookings.value.push(b)
  // 跳到对应日期并切到日视图，便于看到刚建的预定
  currentDate.value = (payload.date && !isNaN(Date.parse(payload.date)))
    ? new Date(payload.date + 'T00:00:00')
    : currentDate.value
  viewMode.value = 'day'
}

// ---- 滚动定位 ----
const calCardRef = ref(null)
const formCardRef = ref(null)
function scrollTo(elRef) {
  elRef.value?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}
</script>

<style scoped>
.equip-booking {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 70:15 内容区 gap 16 */
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
.crumb-current,
.crumb-sep {
  color: var(--color-placeholder);
}

/* 页头（画布 70:17：标题组 gap 6；操作组 gap 8，按钮 36 高、无图标 70:23 / 70:25） */
.eb-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.eb-head-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

/* 主区两栏 70:27（gap 16） */
.eb-main {
  display: flex;
  align-items: flex-start;
  gap: 16px;
}

/* ---------- 卡片-设备列表 70:28 ---------- */
.dev-card {
  width: 300px;
  flex-shrink: 0;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
}
.dev-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.dev-head-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
}
.dev-count {
  height: 20px;
  display: inline-flex;
  align-items: center;
  padding: 0 8px;
  border-radius: 10px;
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-size: 11px;
  font-weight: 500;
  font-family: var(--font-en);
}
.dev-search {
  height: 36px;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0 10px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  color: var(--color-placeholder);
  flex-shrink: 0;
}
.dev-search input {
  flex: 1;
  min-width: 0;
  border: none;
  outline: none;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  background: transparent;
}
.dev-search input::placeholder {
  color: var(--color-placeholder);
}
.dev-search:focus-within {
  border-color: var(--color-primary);
}
.dev-list {
  display: flex;
  flex-direction: column;
  gap: 4px; /* 画布 70:35：行 h53 + gap4 → 卡高 423 */
}
.dev-empty {
  margin: 0;
  padding: 24px 0;
  text-align: center;
  font-size: 12px;
  color: var(--color-placeholder);
}
.dev-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 8px 8px 10px; /* 画布 70:36 padding: left10 / right8 / top8 / bottom8 */
  border: none;
  border-radius: 8px;
  background: transparent;
  text-align: left;
  transition: background 0.12s ease;
}
.dev-item:hover {
  background: var(--color-fill-soft);
}
/* 选中态：画布 70:36 仅 #F0F6FF 底色、**无描边** */
.dev-item.active {
  background: #F0F6FF;
}
.dev-thumb {
  width: 36px;
  height: 36px;
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  background: #DBE4F2;
  color: #104DA9;
  font-size: 14px;
  font-weight: 500;
}
.dev-meta {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px; /* 画布 70:39 gap 2 */
}
.dev-name {
  font-size: 13px;
  color: var(--color-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.dev-model {
  font-size: 12px;
  color: var(--color-text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.dev-status,
.cc-status {
  height: 20px;
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  padding: 0 8px;
  border-radius: 10px;
  font-size: 11px;
  font-weight: 500;
  white-space: nowrap;
}
.dev-note {
  margin: 0;
  padding: 0 2px; /* 画布 70:76 */
  font-size: 11px;
  line-height: 1.45;
  color: var(--color-placeholder);
}

/* ---------- 右栏 70:78 ---------- */
.eb-right {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

/* ---------- 卡片-占用日历 70:79（pad 20 / gap 14） ---------- */
.cal-card {
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 14px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
}
.cal-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.cal-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
}
.cal-tools {
  display: flex;
  align-items: center;
  gap: 8px;
}
/* 日期步进 70:83（h32 / pad 0 10 / gap10 / r8 / 描边 #E4E4E7） */
.date-step {
  height: 32px;
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 0 10px;
  border: 1px solid var(--color-border);
  border-radius: 8px;
}
.step-btn {
  border: none;
  background: none;
  padding: 0;
  font-size: 14px;
  line-height: 1;
  color: var(--color-text-secondary);
}
.step-btn:hover {
  color: var(--color-text);
}
.step-label {
  font-size: 13px;
  color: var(--color-text-menu);
  font-family: var(--font-en);
  white-space: nowrap;
}
/* 视图切换 70:87（h32 / pad3 / gap2 / r8 / #F4F4F5；项 h26 / pad 0 12 / r6） */
.seg {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 3px;
  height: 32px;
  background: var(--color-fill-soft);
  border-radius: 8px;
}
.seg-btn {
  height: 26px;
  padding: 0 12px;
  border: none;
  background: transparent;
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-text-secondary);
  transition: all 0.12s ease;
}
.seg-btn.active {
  background: var(--color-card);
  color: var(--color-text);
}
/* 当前设备条 70:198（h36 / pad 12px 8px / r8 / #F0F6FF / gap 8） */
.cal-current {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  min-height: 36px;
  border-radius: 8px;
  background: var(--color-active-bg);
}
.cc-name {
  font-size: 13px;
  color: var(--color-text);
  white-space: nowrap;
}
.cc-hint {
  flex: 1;
  min-width: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
/* 滚动提示 70:839 / 70:846（pad-left 44 / 11px #C4C4CC） */
.cal-scroll-hint {
  padding-left: 44px;
  font-size: 11px;
  line-height: 16px;
  color: #C4C4CC;
}
.cal-body {
  display: flex;
  flex-direction: column;
}
/* 图例 70:148（gap 16 / pad-left 162） */
.cal-legend {
  display: flex;
  align-items: center;
  gap: 16px;
  padding-left: 162px;
}
.lg-item {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: var(--color-text-secondary);
}
.lg-dot {
  width: 10px;
  height: 10px;
  border-radius: 3px;
  flex-shrink: 0;
}

/* ---------- 卡片-新建预定 70:161（pad 20 / gap 14） ---------- */
.form-card {
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 14px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
}
.form-head {
  display: flex;
  align-items: center;
  gap: 10px; /* 画布 70:162 gap 10 */
}
.form-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
}
.form-sub {
  flex: 1;
  min-width: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
