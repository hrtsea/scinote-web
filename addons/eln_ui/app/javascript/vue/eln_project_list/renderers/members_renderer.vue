<template>
  <!--
    访问权限列 = 旧版渲染（对齐 ELN系统-Vue3 / 旧 addon blob）：
      头像圆点（浅底+深字，最多 3 个）叠加 + 「+N」气泡；
      组授予（kind==='group'）画人形图标，个人画首字母；
      每个头像 title = 成员名（旧版同款），整组 title 兜底列出全部成员名。
    文件夹行不出（旧版 `v-if="!p.folder"`）。
    ⚠ 数据已由后端截断：payload 的 members 就是前 3 个，`extra` 是余量 ——
      这里**不要**再按 length 推算隐藏数，否则会把 +N 算重。
  -->
  <div
    v-if="!isFolder"
    class="flex items-center h-full"
    :title="allNamesTitle"
  >
    <span
      v-for="(m, i) in visible"
      :key="i"
      class="flex items-center justify-center w-6 h-6 rounded-full shrink-0 border-2 text-[11px] font-medium"
      :class="i > 0 ? '-ml-[6px]' : ''"
      :style="[avatarStyle(m.color), { borderColor: AVATAR_BORDER }]"
      :title="m.name"
    >
      <svg
        v-if="m.kind === 'group'"
        viewBox="0 0 24 24"
        width="13"
        height="13"
        aria-hidden="true"
      >
        <path
          fill="currentColor"
          d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5s-3 1.34-3 3 1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"
        />
      </svg>
      <template v-else>{{ m.initial }}</template>
    </span>
    <span
      v-if="extra > 0"
      class="-ml-[6px] flex items-center justify-center w-6 h-6 rounded-full shrink-0 border-2 text-[10px] font-medium"
      :style="[{ background: AVATAR_MORE.background, color: AVATAR_MORE.color }, { borderColor: AVATAR_BORDER }]"
    >
      +{{ extra }}
    </span>
  </div>
</template>

<script>
import { avatarStyle, AVATAR_BORDER, AVATAR_MORE } from './avatar_palette.js';

export default {
  name: 'ElnMembersRenderer',
  props: {
    params: { required: true }
  },
  data() {
    return { AVATAR_BORDER, AVATAR_MORE };
  },
  computed: {
    isFolder() {
      return !!(this.params.data && this.params.data.folder);
    },
    // field 是 members ⇒ params.value 即成员数组（后端已只给前 3 个）
    visible() {
      return (this.params.value || []).slice(0, 3);
    },
    extra() {
      return (this.params.data && this.params.data.extra) || 0;
    },
    allNamesTitle() {
      const names = (this.params.value || []).map((m) => m && m.name).filter(Boolean);
      return names.join('\n');
    }
  },
  methods: { avatarStyle }
};
</script>
