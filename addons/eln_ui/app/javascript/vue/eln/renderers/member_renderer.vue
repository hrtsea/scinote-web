<template>
  <!--
    AG Grid 单元格渲染器：成员 / 负责人（圆头像 + 姓名）。

    用法（columnDefs 内）：
      { field: 'name', headerName: '成员', cellRenderer: MemberRenderer }
      { field: 'ownerName', headerName: '负责人', cellRenderer: MemberRenderer,
        cellRendererParams: { sourceField: 'owner' } }   // 读 params.data.owner 这个子对象

    ★ 配色映射复用原型唯一那份 `avatarPalette`（data/mock.js 导出），不新造一份色表 ——
      否则列表头像与详情页头像会长得不一样（同一事实只许一个真源）。
      入参 `color` 是 palette 的 key（blue/green/...）；给不出就回落 blue（与原型 avatarStyle 同行为）。

    ⚠ 非 scoped 样式：单元格 DOM 由 ag-grid-vue3 动态 mount，拿不到 scopeId。
  -->
  <span class="eln-member-cell">
    <span class="eln-member-avatar" :style="avatarStyle">{{ initial }}</span>
    <span class="eln-member-name" :title="name">{{ name }}</span>
  </span>
</template>

<script>
import { avatarPalette } from '../data/mock';

export default {
  name: 'ElnMemberRenderer',
  props: {
    params: { required: true }
  },
  computed: {
    row() {
      return (this.params && this.params.data) || {};
    },
    // 成员表：行本身就是成员对象；实验表：行里的 owner 才是人 ⇒ 由 sourceField 指定。
    source() {
      const f = this.params && this.params.sourceField;
      if (f && this.row && this.row[f] && typeof this.row[f] === 'object') return this.row[f];
      return this.row;
    },
    name() {
      const n = this.source && this.source.name;
      return n === null || n === undefined || n === '' ? '—' : String(n);
    },
    initial() {
      const i = this.source && this.source.initial;
      if (i) return String(i);
      return this.name === '—' ? '·' : this.name.slice(0, 1);
    },
    avatarStyle() {
      const c = avatarPalette[(this.source && this.source.color)] || avatarPalette.blue;
      return { background: c.bg, color: c.fg };
    }
  }
};
</script>

<!--
  ⚠ 非 scoped（原因见上）。类名 eln-member-* 自成一套，不复用页面 scoped 的
    `.member-cell` / `.avatar` —— 那两个类选择器带 [data-v-xxx]，加不到单元格上。
-->
<style>
.eln-member-cell {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.eln-member-avatar {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  font-size: 12px;
  font-weight: 600;
  flex: 0 0 auto;
}
.eln-member-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
