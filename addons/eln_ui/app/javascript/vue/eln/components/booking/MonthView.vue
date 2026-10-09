<template>
  <!-- 月视图（画布 70:418）：方格月历，日期格内事件 chip -->
  <div class="month-view">
    <div class="mv-weekhead">
      <span v-for="(w, i) in WEEKDAY_CN" :key="i" class="mv-wh">周{{ w }}</span>
    </div>
    <div class="mv-grid">
      <div v-for="(week, w) in matrix" :key="w" class="mv-week">
        <div
          v-for="(d, i) in week"
          :key="i"
          class="mv-cell"
          :class="{ today: sameDay(d, TODAY), other: d.getMonth() !== focusMonth }"
        >
          <div class="mv-cell-head">
            <span class="mv-dn">{{ d.getMonth() + 1 }}/{{ d.getDate() }}</span>
            <span v-if="sameDay(d, TODAY)" class="mv-today">· 今天</span>
          </div>
          <div class="mv-chips">
            <div
              v-for="ev in cellEvents(d).slice(0, 2)"
              :key="ev.id"
              class="mv-chip"
              :style="chipStyle(ev)"
              :title="`${ev.title} ${ev.start}–${ev.end} · ${ev.owner}`"
            >
              {{ bookingLabelShort(ev) }}
            </div>
            <div v-if="cellEvents(d).length > 2" class="mv-more">+{{ cellEvents(d).length - 2 }}</div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { sameDay, ymd, TODAY, WEEKDAY_CN, bookingTypeStyle, bookingLabelShort } from '../../data/equipment.js'

const props = defineProps({
  matrix: { type: Array, required: true }, // 周数组，每周 7 个 Date
  eventsMap: { type: Object, default: () => ({}) }, // ymd -> 事件数组
  focusMonth: { type: Number, required: true } // 0-11，用于区分跨月灰字
})

function cellEvents(d) {
  return props.eventsMap[ymd(d)] || []
}
function chipStyle(ev) {
  const st = bookingTypeStyle[ev.type] || bookingTypeStyle.occupied
  return { background: st.bg, color: st.fg }
}
</script>

<style scoped>
.month-view {
  display: flex;
  flex-direction: column;
}
.mv-weekhead {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  border-bottom: 1px solid var(--color-border);
}
.mv-wh {
  padding: 8px 0;
  text-align: center;
  font-size: 11px;
  color: var(--color-text-secondary);
}
/* 月视图格（画布 70:418 实测）：白卡上 #FAFAFA 圆角格，格间 gap 4；
   今天格 #F0F6FF 底 + 主色 1px 内描边；日期为「M/D」，今天追加「· 今天」 */
.mv-grid {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.mv-week {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 4px;
}
.mv-cell {
  min-height: 76px;
  padding: 6px 8px;
  background: var(--color-page-bg);
  border-radius: 6px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.mv-cell.other {
  background: var(--color-page-bg);
}
.mv-cell.today {
  background: #F0F6FF;
  box-shadow: inset 0 0 0 1px var(--color-primary);
}
.mv-cell-head {
  display: flex;
  align-items: center;
  gap: 4px;
}
.mv-dn {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
  font-family: var(--font-en);
}
.mv-cell.other .mv-dn {
  color: var(--color-placeholder);
}
.mv-cell.today .mv-dn,
.mv-cell.today .mv-today {
  color: var(--color-primary);
}
.mv-today {
  font-size: 12px;
}
.mv-chips {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.mv-chip {
  font-size: 10px;
  line-height: 1.4;
  padding: 1px 6px;
  border-radius: 4px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.mv-more {
  font-size: 10px;
  color: var(--color-text-secondary);
  padding-left: 2px;
}
</style>
