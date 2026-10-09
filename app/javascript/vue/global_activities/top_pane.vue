<script setup>
// 顶部操作区：展开全部 / 折叠全部 / 搜索框。
// 折叠/展开沿用 Bootstrap 3 的 .collapse（document 委托），这里只发 programmatic show/hide。
// 搜索框在原 Gen-1 实现中无 JS 行为（纯占位），此处保持原样渲染。
// 注意：.ga-tags-container（已选筛选标签 + 保存/清除筛选）仍由全局 side_pane.js 管理，不归本组件。
import { getCurrentInstance } from 'vue';

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

function jQuery() {
  return window.jQuery;
}

function expandAll(ev) {
  ev.preventDefault();
  const $ = jQuery();
  if ($) $('.activities-group').collapse('show');
}

function collapseAll(ev) {
  ev.preventDefault();
  const $ = jQuery();
  if ($) $('.activities-group').collapse('hide');
}
</script>

<template>
  <div class="ga-actions">
    <div class="sci-btn-group">
      <a
        id="global-activities-expand-all"
        class="hide-actions btn btn-light"
        href="#"
        data-turbolinks="false"
        @click="expandAll"
      >
        <i class="sn-icon sn-icon-down"></i>{{ i18n.t('activities.index.expand_all') }}
      </a>
      <a
        id="global-activities-colapse-all"
        class="hide-actions btn btn-light"
        href="#"
        data-turbolinks="false"
        @click="collapseAll"
      >
        <i class="sn-icon sn-icon-up"></i>{{ i18n.t('activities.index.collapse_all') }}
      </a>
    </div>
    <div class="ga-search-container">
      <input type="text" class="search-field" placeholder="Search..." aria-describedby="basic-addon1">
      <i class="sn-icon sn-icon-search"></i>
    </div>
  </div>
</template>
