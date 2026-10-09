<template>
  <!-- 日视图（画布 70:92 时间刻度 + 70:108 日历行）：
       标签列 130 / 时间轴 h48 r8 #FAFAFA / 2 小时 92px（≈46px 每小时），08:00–22:00 -->
  <div class="day-view">
    <!-- 时间刻度 70:92（h16：标签占位 142 + 7 列 × 92） -->
    <div class="dv-head">
      <div class="dv-corner"></div>
      <div class="dv-scale">
        <span v-for="h in labelHours" :key="h" class="dv-hour-label">{{ pad(h) }}:00</span>
      </div>
    </div>

    <!-- 日历行-设备泳道 70:108（gap 12；设备标签 130 + 时间轴 fill） -->
    <div class="dv-lane">
      <div class="dv-device-label">
        <div class="dv-device-name">{{ device.name }}</div>
        <div class="dv-device-code">{{ device.code }}</div>
      </div>
      <div class="dv-track">
        <div
          v-for="ev in events"
          :key="ev.id"
          class="dv-block"
          :style="blockStyle(ev)"
          :title="`${ev.title} ${ev.start}–${ev.end} · ${ev.owner}`"
        >
          {{ bookingLabel(ev) }}
        </div>
        <div v-if="events.length === 0" class="dv-empty">当日无预约</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue/dist/vue.esm-bundler.js'
import { pad, hmToMinutes, bookingTypeStyle, bookingLabel } from '../../data/equipment.js'

const props = defineProps({
  device: { type: Object, required: true },
  date: { type: Date, required: true },
  events: { type: Array, default: () => [] }
})

const DAY_START = 8
const DAY_END = 22
const PX = 46

// 刻度列 08:00–20:00 共 7 列（每列 2 小时 = 92px，与画布 70:92 逐格对齐）
const labelHours = computed(() => {
  const len = (DAY_END - DAY_START) / 2
  return Array.from({ length: len }, (_, i) => DAY_START + i * 2)
})

function xOf(min) {
  return ((min - DAY_START * 60) / 60) * PX
}

function blockStyle(ev) {
  const s = hmToMinutes(ev.start)
  const e = hmToMinutes(ev.end)
  const st = bookingTypeStyle[ev.type] || bookingTypeStyle.occupied
  return {
    left: xOf(s) + 'px',
    width: Math.max(((e - s) / 60) * PX, 28) + 'px',
    background: st.bg,
    color: st.fg
  }
}
</script>

<style scoped>
.day-view {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
/* 时间刻度（画布 70:92：标签占位 142 = 设备标签 130 + 行 gap 12） */
.dv-head {
  display: flex;
  align-items: center;
  height: 16px;
}
.dv-corner {
  width: 142px;
  flex-shrink: 0;
}
.dv-scale {
  flex: 1;
  min-width: 0;
  display: flex;
}
.dv-hour-label {
  width: 92px; /* 画布 70:94/70:96… 每列 92 */
  flex-shrink: 0;
  font-size: 11px;
  color: var(--color-text-secondary);
  font-family: var(--font-en);
}
/* 设备泳道（画布 70:108：gap 12 / h48） */
.dv-lane {
  display: flex;
  align-items: center;
  gap: 12px;
}
.dv-device-label {
  width: 130px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.dv-device-name {
  font-size: 13px;
  color: var(--color-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.dv-device-code {
  font-size: 12px;
  color: var(--color-text-secondary);
  font-family: var(--font-en);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
/* 时间轴（画布 70:112：h48 / r8 / #FAFAFA） */
.dv-track {
  flex: 1;
  min-width: 0;
  position: relative;
  height: 48px;
  border-radius: 8px;
  background: var(--color-page-bg);
}
.dv-block {
  position: absolute;
  top: 0;
  height: 48px;
  border-radius: 6px;
  padding: 0 8px;
  /* 单行居中（画布 70:114 主/次轴均居中）；display:block + line-height 才能让
     text-overflow:ellipsis 生效（flex 容器上直接放文本会失效） */
  display: block;
  line-height: 48px;
  overflow: hidden;
  font-size: 11px;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.dv-empty {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  color: var(--color-placeholder);
}
</style>
