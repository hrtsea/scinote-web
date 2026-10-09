<template>
  <!--
    AG Grid 单元格渲染器：把单元格文本渲染成「可点链接」，用于列表下钻。

    为什么要有它（2026-10-09）：
      资源中心「资源申请」表改用宿主 shared/datatable/table.vue（AG Grid）后，
      「申请编号」列退化成纯文本，下钻链路断了；原型里这里是
      `<router-link :to="`/eln_res_apply/${a.no}`">`（ELN系统-Vue3/src/views/ResCenter.vue L325）。
      本组件把这层链接补回 AG Grid —— 与项目列表 ElnNameRenderer 同一套路
      （eln_project_list/renderers/name_renderer.vue），props 契约同为 AG Grid 的 `params`。

    ★ 目标地址**必须**来自行数据（`params.data.detailUrl`），由后端按宿主真实路由算好下发
      （res_center_payload#apply_detail_url）。前端绝不自己拼 /eln_xxx
      —— 铁律「路径词汇表只一套」，见 entries/modifiers/router_link_host.js 头注。
    ★ URL 取不到 → 回落纯文本，不做「看着能点、点了 404」的假链接。
  -->
  <a
    v-if="href"
    :href="href"
    class="eln-cell-link"
    :title="text"
    data-e2e="e2e-CO-rc-cell-link"
  >{{ text }}</a>
  <span v-else class="eln-cell-plain" :title="text">{{ text }}</span>
</template>

<script>
export default {
  name: 'ElnLinkRenderer',
  props: {
    params: { required: true }
  },
  computed: {
    row() {
      return (this.params && this.params.data) || {};
    },
    // 显示文本 = 本列字段值（AG Grid 把 field 的值放进 params.value）
    text() {
      const v = this.params ? this.params.value : null;
      return v === null || v === undefined || v === '' ? '—' : String(v);
    },
    // URL 字段名可被 cellRendererParams.urlField 覆盖，默认读 detailUrl
    urlField() {
      return (this.params && this.params.urlField) || 'detailUrl';
    },
    href() {
      return this.row[this.urlField] || null;
    }
  }
};
</script>

<!--
  ⚠ 非 scoped：单元格 DOM 由 ag-grid-vue3 在**本 SFC 的模板之外**创建
  （渲染器实例由框架包装器动态 mount，拿不到父组件的 scopeId），
  scoped 选择器加不上 data 属性、样式会静默失效。
  ⚠ 类名用 eln- 前缀且不复用页面里的 .rc-link —— 避免与 ResCenter.vue 的 scoped 规则重名。
-->
<style>
.eln-cell-link {
  color: var(--color-primary, #2563EB);
  text-decoration: none;
  cursor: pointer;
}
.eln-cell-link:hover {
  text-decoration: underline;
}
.eln-cell-plain {
  color: inherit;
}
</style>
