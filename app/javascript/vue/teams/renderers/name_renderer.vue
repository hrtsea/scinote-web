<template>
  <!--
    工作区列表「名称」列 cellRenderer（ADR-0034 rev3）。
    仅在「可管理该工作区」时渲染链接（与后端 can_manage 的 load_team 门槛同源），
    否则纯文本 —— 避免渲染出点进去 403 的链接。以直接组件引用方式挂到 columnDefs
    （与 /projects 的 FavoriteRenderer 同法，规避 AG Grid 字符串组件的注册作用域问题）。
  -->
  <a v-if="params.data && params.data.can_manage && params.data.members_url"
     :href="params.data.members_url"
     :title="params.value"
  >{{ params.value }}</a>
  <span v-else>{{ params.value }}</span>
</template>

<script>
export default {
  name: 'TeamsNameRenderer',
  props: {
    params: { type: Object, required: true }
  }
};
</script>
