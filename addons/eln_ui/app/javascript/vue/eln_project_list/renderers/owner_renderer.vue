<template>
  <div class="flex items-center gap-2 h-full min-w-0">
    <div
      class="flex items-center justify-center w-6 h-6 rounded-full shrink-0 select-none text-[11px] font-medium border-2"
      :style="[avatarStyle(owner.color), { borderColor: AVATAR_BORDER }]"
    >
      {{ initial }}
    </div>
    <span class="truncate text-sn-dark-grey" :title="name">{{ name }}</span>
  </div>
</template>

<script>
import { avatarStyle, AVATAR_BORDER } from './avatar_palette.js';

// ELN 专属：负责人 = 头像圆点 + 首字母 + 姓名。
// 头像与「访问权限」列共用同一调色板（avatar_palette.js）—— 旧版两列本就用同一个
// avatarStyle，保持一张表里只有一种头像语言。
export default {
  name: 'ElnOwnerRenderer',
  props: {
    params: { required: true }
  },
  data() {
    return { AVATAR_BORDER };
  },
  methods: { avatarStyle },
  computed: {
    owner() {
      return (this.params.data && this.params.data.owner) || {};
    },
    name() {
      return this.owner.name || '—';
    },
    initial() {
      return this.owner.initial || '·';
    }
  }
};
</script>
