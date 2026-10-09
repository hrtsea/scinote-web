<template>
  <div v-if="status" class="flex items-center gap-2 h-full">
    <div class="w-2.5 h-2.5 rounded-full shrink-0" :style="{ backgroundColor: dotColor }"></div>
    <span class="truncate text-sn-dark-grey">{{ label }}</span>
  </div>
</template>

<script>
// ELN 专属：状态色点 + 中文标签。
// 取值口径抽到 renderers/status_map.js（表格与卡片共用同一份，避免第二真源）。
import { elnStatus } from './status_map';

export default {
  name: 'ElnStatusRenderer',
  props: {
    params: { required: true }
  },
  computed: {
    status() {
      return this.params.data && this.params.data.status;
    },
    label() {
      return elnStatus(this.status).label || this.status;
    },
    dotColor() {
      return elnStatus(this.status).color;
    }
  }
};
</script>
