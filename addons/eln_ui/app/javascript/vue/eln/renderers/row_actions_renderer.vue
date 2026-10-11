<template>
  <!--
    AG Grid 单元格渲染器：行内多操作（文字按钮组）。

    用法（columnDefs 内）：
      {
        field: 'actions', headerName: '操作', sortable: false, resizable: false, width: 180,
        cellRenderer: RowActionsRenderer,
        cellRendererParams: {
          actions: [
            { label: '编辑',      handler: (row) => openMetricModal(row) },
            { label: '切换达标',  handler: (row) => toggleMetric(row) },
            { label: '删除',      tone: 'danger', handler: (row) => removeMetric(row) }
          ]
        }
      }

    ★ handler 由 columnDefs 的**宿主组件**闭包提供（页面自己的 CRUD 方法），
      渲染器只负责画与转发 —— 不在渲染器里存放行数据相关的业务判断。
    ★ 无 handler 的条目渲染成「看着能点、但不做事」的占位按钮（原型里
      「预览 · 下载」「变更角色」就是这种尚未接线的占位），语义与原页面一致。

    ⚠ 非 scoped 样式：单元格 DOM 由 ag-grid-vue3 在本 SFC 模板之外动态 mount。
    ⚠ `@click.stop`：不阻止冒泡会让宿主 datatable 的 cellClicked 把「点按钮」当成
      「点单元格」（进而触发行选择逻辑），按钮与单元格语义就混了。
  -->
  <span class="eln-cell-actions">
    <template v-for="(action, i) in actions" :key="i">
      <!-- 有 href 的条目 = 真链接（新开标签去下钻）；其余 = 文字按钮 -->
      <a
        v-if="action.href"
        class="eln-cell-action"
        :class="{ 'eln-cell-action--danger': action.tone === 'danger' }"
        :href="action.href"
        :title="action.title || action.label"
        target="_blank"
        rel="noopener"
      >{{ action.label }}</a>
      <button
        v-else
        type="button"
        class="eln-cell-action"
        :class="{ 'eln-cell-action--danger': action.tone === 'danger' }"
        :disabled="action.disabled === true"
        :title="action.title || action.label"
        @click.stop="run(action)"
      >{{ action.label }}</button>
    </template>
  </span>
</template>

<script>
export default {
  name: 'ElnRowActionsRenderer',
  props: {
    params: { required: true }
  },
  computed: {
    row() {
      return (this.params && this.params.data) || {};
    },
    // actions 允许两种形态：
    //   数组            —— 全行同一组动作；
    //   函数 (row)=>[]  —— 逐行不同（如成员的「变更角色」对 Owner 不显示）。
    actions() {
      const src = this.params && this.params.actions;
      const list = typeof src === 'function' ? src(this.row) : src;
      return Array.isArray(list) ? list.filter((a) => a && a.label) : [];
    }
  },
  methods: {
    run(action) {
      if (action && typeof action.handler === 'function') action.handler(this.row);
    }
  }
};
</script>

<!--
  ⚠ 非 scoped（原因见上）。类名 eln-cell-action* 自成一套，不复用页面 scoped 的
    `.table-link` —— 那个选择器带 [data-v-xxx]，加不到单元格 DOM 上（会静默失效）。
  视觉对齐原页面 .table-link：主色文字、hover 下划线、danger 用红。
-->
<style>
.eln-cell-actions {
  display: inline-flex;
  align-items: center;
  gap: 12px;
  white-space: nowrap;
}
.eln-cell-action {
  padding: 0;
  border: 0;
  background: none;
  color: var(--color-primary, #2563eb);
  font-size: inherit;
  line-height: 1;
  cursor: pointer;
  text-decoration: none;
}
.eln-cell-action:hover {
  text-decoration: underline;
}
.eln-cell-action:disabled {
  color: var(--text-muted, #94a3b8);
  cursor: default;
}
.eln-cell-action:disabled:hover {
  text-decoration: none;
}
.eln-cell-action--danger {
  color: var(--color-danger, #dc2626);
}
</style>
