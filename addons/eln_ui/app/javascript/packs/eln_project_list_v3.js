// ELN UI —— 项目列表页（Vue3 原型栈）的宿主构建入口
//
// 为什么单独一个 pack（而不是直接在 webpack entry 里写 entry 本身）：
//   其余 5 页（res_center / project_detail / ...）的 pack 都是同一形状 ——
//   只 re-import 对应 entry，不含任何逻辑。这里照抄同一形状，保持一致性。
//
// ⚠ 2026-10-11 关键背景（切真源）：
//   生产页此前加载的是 `eln_vue3/eln_project_list.js` —— 一份 152KB、
//   5 行的**手写压缩 blob**，未纳入 git、全仓**找不到任何构建脚本**。
//   后果：DateField 这类组件改动编译进 webpack 后也永远不会到生产页
//   （浏览器实测 `dp__menu` 标记在生产产物里为0）。现改为由本 pack 统一构建，
//   `entries/project_list.js` 成为唯一真源。
//   旧 `project_list_v1` 测试 entry（vue/eln/views/ProjectList.vue 那套）
//   保持原样不动 —— 它挂载点相同但组件不同，是 V2 比对页，不是生产页。
import '../vue/eln/entries/project_list';