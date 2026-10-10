<template>
  <!-- 宿主原生 CommentsRenderer 的 ELN 薄封装（spec SCN-PROJ-LIST-11）。
       为什么需要封装而不直接用宿主那份：
         宿主 comments.vue 的 objectType 靠 `params.data.type` 做switch
           （'my_modules' → MyModule / 'projects' → Project）。
         而 ELN 的行经 DataTable#formatData（table.vue:661 `{...item.attributes}`）摊平后，
           AMS 放在**顶层**的 "type":"project"（单数，ELN 词汇表）**不在 attributes 里**
           ⇒ 宿主那份拿不到 type ⇒ objectType 落空字符串 ⇒ 侧栏打不开。
         ⚠ 也不能改后端把 type 下成 'projects'（复数）：ELN 全链路用**单数**
           （row_action_modal.vue:180 判 `row.type === 'project_folder'`、
            list.vue:501 映射成复数喂宿主端点），改行形状会连带打破这两处。
       ⇒ 这里只做一件事：给渲染器补一个**派生字段** `type`，映射单数→宿主认识的复数，
         其余行为完全交给宿主组件（点击委托、未读小红点、计数回写）。
  -->
  <HostCommentsRenderer v-bind="hostParams" />
</template>

<script>
// 宿主原生渲染器本体（单一真源，不复制逻辑）。
import HostCommentsRenderer from 'shared/datatable/renderers/comments.vue';

export default {
  name: 'ElnCommentsRenderer',
  components: { HostCommentsRenderer },
  props: {
    params: { required: true }
  },
  computed: {
    hostParams() {
      const data = this.params.data || {};
      // ELN 单数 → 宿主 switch 认识的复数；文件夹行不渲染（宿主 v-if 已挡，这里给出安全值）。
      let type = '';
      if (!data.folder) {
        if (data.type === 'project' || !data.type) type = 'projects';
      }
      return {
        ...this.params,
        data: { ...data, type }
      };
    }
  }
};
</script>