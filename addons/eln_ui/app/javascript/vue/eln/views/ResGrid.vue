<template>
  <!--
    资源中心 5 张表 + 项目详情 7 张表统一薄封装：底层复用宿主 shared/datatable/table.vue
    （AG Grid v32.3.9，与 /projects 同引擎同版本），收口为「只读网格」形态：
      · 无勾选 / 无行菜单 / 无列管理 / 无卡片视图 / 不写 user_settings 列状态
      · 筛选走 postParams（宿主组件只在 loadMethod=post 时发出 postParams）
      · 服务端分页（scrollMode='pages'），排序/筛选全部服务端收口
    高度策略（见 ADR-0047）：默认不传 height ⇒ 走宿主 autoHeight（AG Grid 原生 domLayout:
      'autoHeight'，网格随当前页行数自行撑开，无内部滚动条，移动端/内嵌页友好）；
      传 height ⇒ 维持固定高度 + 内部滚动（保留作个别长表的 override 旋钮）。
  -->
  <div class="rc-grid-host">
    <DataTable
      :data-url="dataUrl"
      :table-id="tableId"
      :column-defs="columnDefs"
      :post-params="postParams"
      :reloading-table="reloadingTable"
      :load-method="'post'"
      :with-checkboxes="false"
      :with-row-menu="false"
      :with-pinned-columns="false"
      :hide-columns-managment="true"
      :skip-save-table-state="true"
      :scroll-mode="'pages'"
      :toolbar-actions="{}"
      :table-only="true"
      :auto-height="!height"
      @table-reloaded="onTableReloaded"
    />
  </div>
</template>

<script setup>
import DataTable from 'shared/datatable/table.vue'

const props = defineProps({
  dataUrl: { type: String, required: true },
  tableId: { type: String, required: true },
  columnDefs: { type: Array, default: () => [] },
  postParams: { type: Object, default: () => ({}) },
  // 任一筛选变化 → 自增触发宿主组件 reloadingTable watch → 重新拉数据
  reloadingTable: { type: [Boolean, Number], default: false },
  // 不传 height ⇒ 走宿主 autoHeight（无内部滚动条，见 ADR-0047）；
  // 传 height ⇒ 维持固定高度 + 内部滚动（保留作个别长表的 override 旋钮）。
  height: { type: String, default: null }
})

// 宿主栈每次加载完成都发 `tableReloaded(rowData, {filtered})`。
// 2026-10-11 加透传：项目详情页页头的「指标 N/M 达标」徽标**必须**由同一份网格行算出来
// （原先读 payload 快照 ⇒ 表改了徽标不动，正是本仓禁止的「同一事实两个真源」）。
const emit = defineEmits(['tableReloaded'])

function onTableReloaded(rows, meta) {
  emit('tableReloaded', rows, meta)
}
</script>

<style scoped>
.rc-grid-host {
  width: 100%;
}
</style>
