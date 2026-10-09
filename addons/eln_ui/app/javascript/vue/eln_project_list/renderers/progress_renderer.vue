<template>
  <div v-if="!isFolder" class="flex flex-col justify-center h-full leading-4 min-w-0">
    <div class="text-sm">
      <span class="font-semibold text-sn-black">{{ completed }}</span>
      <span class="text-sn-sleepy-grey"> / {{ total }}</span>
    </div>
    <div class="w-16 h-1 mt-1 rounded bg-sn-light-grey overflow-hidden">
      <div class="h-full rounded transition-all"
           :style="{ width: pct + '%', backgroundColor: barColor }"></div>
    </div>
  </div>
</template>

<script>
// ELN 专属：完成数 / 总数 + 细进度条（已完成实验、已完成任务共用）。
// 字段由 cellRendererParams 下发（completedField/totalField），与原生 counter.vue 同思路，
// 但不依赖 i18n label，直接显示「X / Y」。
export default {
  name: 'ElnProgressRenderer',
  props: {
    params: { required: true },
    completedField: { type: String, default: 'completed' },
    totalField: { type: String, default: 'total' }
  },
  computed: {
    isFolder() {
      return !!(this.params.data && this.params.data.folder);
    },
    completed() {
      return Number((this.params.data && this.params.data[this.completedField]) || 0);
    },
    total() {
      return Number((this.params.data && this.params.data[this.totalField]) || 0);
    },
    pct() {
      if (!this.total) return 0;
      return Math.min(100, Math.round((this.completed / this.total) * 100));
    },
    barColor() {
      return this.params.data.archivedOn ? '#98A2B3' : '#3B99FD';
    }
  }
};
</script>
