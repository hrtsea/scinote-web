<template>
  <!--
    AG Grid 单元格渲染器：状态徽章（复用原型全局类 `.eln-badge` / `.eln-badge-<tone>`，
    tokens.css 全局引入 ⇒ 在单元格 DOM 里同样生效）。

    用法（columnDefs 内）：
      {
        field: 'stateLabel', headerName: '关闭状态',
        cellRenderer: StateBadgeRenderer,
        cellRendererParams: { toneOf: (row) => ({ approved: 'green', rejected: 'red' }[row.state] || 'grey') }
      }

    ⚠ 为什么 toneOf 是函数而不是「值→类名」映射表：色彩是**视图层**关注点，
      不该让后端在 attributes 里下发 badgeClass（那会把样式决策塞进数据契约）。
       函数留在 columnDefs 里，谁配的列谁负责配色。
    ⚠ 样式一律写在**非 scoped** <style> 里 —— 单元格 DOM 由 ag-grid-vue3 在本 SFC 模板之外
      动态 mount，拿不到父组件的 scopeId（与 link_renderer.vue 同因）。
  -->
  <span class="eln-badge" :class="`eln-badge-${tone}`" :title="text">{{ text }}</span>
</template>

<script>
export default {
  name: 'ElnStateBadgeRenderer',
  props: {
    params: { required: true }
  },
  computed: {
    row() {
      return (this.params && this.params.data) || {};
    },
    text() {
      const v = this.params ? this.params.value : null;
      return v === null || v === undefined || v === '' ? '—' : String(v);
    },
    tone() {
      const fn = this.params && this.params.toneOf;
      return typeof fn === 'function' ? fn(this.row) : 'grey';
    }
  }
};
</script>
