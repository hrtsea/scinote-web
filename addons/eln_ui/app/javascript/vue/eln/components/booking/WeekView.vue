<template>
  <!-- 周视图（画布 70:772 周历表头 + 70:841 时间网格滚动区）：
       刻度列 36 / 7 日列 r6（#FAFAFA，今天 #F0F6FF）/ 24h 纵向滚动 -->
  <div class="week-view">
    <!-- 周历表头 70:772（gap 4：刻度占位 36 + 7 列头 h40） -->
    <div class="wv-head">
      <div class="wv-gutter-head"></div>
      <div
        v-for="(d, i) in days"
        :key="i"
        class="wv-day-head"
        :class="{ today: sameDay(d, TODAY) }"
      >
        <span class="wv-wd">{{ WEEKDAY_CN[i] }}</span>
        <span class="wv-dn" :class="{ circle: sameDay(d, TODAY) }">{{ d.getDate() }}</span>
      </div>
    </div>

    <!-- 滚动区 70:841（视口 480，24h 内容，初始定位 08:00） -->
    <div class="wv-body">
      <div class="wv-scroll" ref="scrollEl">
        <div class="wv-inner" :style="{ height: dayH + 'px' }">
          <!-- 左侧小时刻度 70:797（w36；每格 40px，需显式 top 定位） -->
          <div class="wv-gutter">
            <span
              v-for="h in 24"
              :key="h"
              class="wv-hour"
              :style="{ top: (h - 1) * PX + 'px' }"
            >{{ pad(h - 1) }}:00</span>
          </div>
          <!-- 7 日列 70:810~816（fill / r6 / #FAFAFA；今天 #F0F6FF） -->
          <div
            v-for="(d, i) in days"
            :key="'c' + i"
            class="wv-col"
            :class="{ today: sameDay(d, TODAY) }"
          >
            <div v-for="h in 24" :key="h" class="wv-line"></div>
            <div v-if="sameDay(d, TODAY)" class="wv-now" :style="{ top: yNow + 'px' }">
              <span class="wv-now-dot"></span>
            </div>
            <div
              v-for="ev in eventsByDay[i]"
              :key="ev.id"
              class="wv-ev"
              :style="evStyle(ev)"
              :title="`${ev.title} ${ev.start}–${ev.end} · ${ev.owner}`"
            >
              <div class="wv-ev-time">{{ ev.start }} - {{ ev.end }}</div>
              <div class="wv-ev-title">{{ bookingLabel(ev) }}</div>
            </div>
          </div>
        </div>
      </div>
      <!-- 自定义滚动条 70:842（w6 / r3 / #F4F4F5，滑块 w4 / r2 / #D0D5DD） -->
      <div class="wv-sb"><div class="wv-sb-thumb"></div></div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue/dist/vue.esm-bundler.js'
import {
  pad, hmToMinutes, sameDay, TODAY, WEEKDAY_CN, bookingTypeStyle, bookingLabel,
  HOUR_START, PX_PER_HOUR
} from '../../data/equipment.js'

const props = defineProps({
  days: { type: Array, required: true }, // 7 个 Date
  eventsByDay: { type: Array, required: true } // 长度 7 的二维数组
})

const PX = PX_PER_HOUR // 40
const dayH = 24 * PX // 全天 960px
const scrollEl = ref(null)

function yOf(min) {
  return (min / 60) * PX
}
const yNow = computed(() => {
  const n = new Date()
  return yOf(n.getHours() * 60 + n.getMinutes())
})

function evStyle(ev) {
  const s = hmToMinutes(ev.start)
  const e = hmToMinutes(ev.end)
  const st = bookingTypeStyle[ev.type] || bookingTypeStyle.occupied
  return {
    top: yOf(s) + 2 + 'px',
    height: Math.max(((e - s) / 60) * PX - 4, 18) + 'px',
    background: st.bg,
    color: st.fg
  }
}

onMounted(() => {
  if (scrollEl.value) scrollEl.value.scrollTop = HOUR_START * PX // 定位到 08:00
})
</script>

<style scoped>
.week-view {
  display: flex;
  flex-direction: column;
}
/* 周历表头 70:772（gap 4） */
.wv-head {
  display: flex;
  align-items: stretch;
  gap: 4px;
  flex-shrink: 0;
}
.wv-gutter-head {
  width: 36px;
  flex-shrink: 0;
}
.wv-day-head {
  flex: 1;
  min-width: 0;
  height: 40px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2px;
}
.wv-wd {
  font-size: 11px;
  color: var(--color-text-secondary);
}
.wv-day-head.today .wv-wd {
  color: var(--color-primary); /* 画布 70:778：今天列星期字用主色 */
}
.wv-dn {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  font-family: var(--font-en);
}
.wv-dn.circle {
  background: var(--color-primary);
  color: #fff;
}

/* 滚动区 70:841（gap 6：网格 + 滚动条） */
.wv-body {
  display: flex;
  align-items: flex-start;
  gap: 6px;
}
.wv-scroll {
  flex: 1;
  min-width: 0;
  height: 480px; /* 画布 70:841 视口高 480 */
  overflow-y: auto;
  scrollbar-width: none;
}
.wv-scroll::-webkit-scrollbar {
  display: none;
}
.wv-inner {
  display: flex;
  gap: 4px; /* 画布 70:796 gap 4 */
  position: relative;
}
.wv-gutter {
  width: 36px;
  flex-shrink: 0;
  position: relative;
}
.wv-hour {
  position: absolute;
  left: 0;
  right: 0;
  transform: translateY(-6px);
  text-align: center;
  font-size: 10px;
  color: var(--color-text-secondary);
  font-family: var(--font-en);
}
/* 日列 70:810（r6 / #FAFAFA；今天 #F0F6FF） */
.wv-col {
  flex: 1;
  min-width: 0;
  position: relative;
  border-radius: 6px;
  background: var(--color-page-bg);
}
.wv-col.today {
  background: #F0F6FF; /* 画布 70:811 */
}
.wv-line {
  height: 40px;
  border-bottom: 1px solid var(--color-border);
  box-sizing: border-box;
}
.wv-now {
  position: absolute;
  left: 0;
  right: 0;
  height: 2px;
  background: var(--color-danger);
  z-index: 3;
}
.wv-now-dot {
  position: absolute;
  left: -3px;
  top: -3px;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--color-danger);
}
.wv-ev {
  position: absolute;
  left: 3px;
  right: 3px;
  border-radius: 6px;
  padding: 4px 6px;
  overflow: hidden;
  font-size: 10px;
  line-height: 1.3;
}
.wv-ev-title {
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.wv-ev-time {
  font-family: var(--font-en);
  opacity: 0.85;
}
/* 自定义滚动条 70:842 */
.wv-sb {
  width: 6px;
  height: 480px;
  flex-shrink: 0;
  border-radius: 3px;
  background: var(--color-fill-soft);
  overflow: hidden;
}
.wv-sb-thumb {
  width: 4px;
  height: 240px; /* 画布 70:844 */
  margin: 160px auto 0;
  border-radius: 2px;
  background: #D0D5DD;
}
</style>
