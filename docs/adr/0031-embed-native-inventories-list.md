# ADR-0031：资源台账内嵌原生 Inventories 列表（不新造外壳）

- 状态：已采纳（2026-10-06）
- 决策人：用户（AskUserQuestion 三选一：整页跳转 / 点页签即跳 / **页签内嵌原生列表组件**）
- 相关：DEC-012（自研能力挂载到原生视图，不新造外壳）、`REQ-RESOURCE` / `SCN-RES-1`、`REQ-RES-APPROVER`
- 影响面：`addons/eln_ui/app/views/scinote/eln_ui/res_center/index.html.erb`、`ELN系统-Vue3/src/views/ResCenter.vue`（**零后端 Ruby 改动**）

## 背景

资源中心「资源台账」页签原先自绘一张仓库卡片网格（库名 / 描述 / 条目数 / 「打开原生库存 →」跳
`/repositories/:id`）。这等于把原生 Inventories 列表**又抄了一份**，而且抄不全：没有排序、没有
筛选、没有列自定义、没有归档视图、没有批量操作。用户明确要求「资源台账使用原生的库存列表」，
并选定**页签内嵌原生列表组件**（保留单页上下文，不整页跳出资源中心）。

## 决策

资源台账页签**直接使用原生 `<repositories-table>`**，不保留任何自绘台账 UI。

## 关键事实（实测，勿凭印象改）

原生库存列表**已经是 Vue 3**（`app/javascript/packs/vue/repositories_table.js`）：

```js
const app = createApp();
app.component('RepositoriesTable', RepositoriesTable);
mountWithTurbolinks(app, '#repositoriesTable');   // ← 挂载点是 DOM id
```

它不是 Vue 2 + `vue-haxr` 自定义元素。它依赖 Vue 3 的 mount 语义：**root 组件没有
`render`/`template` 时，拿 `container.innerHTML` 当模板**。组件树
`repositories/table.vue` → `shared/datatable/table.vue`（**AG Grid**），工具栏
（Active state / 搜索 / 列设置）**在组件内**，不在 `views/repositories/toolbar/` 里（那些是
`repositories#show` 的）。数据源 `/repositories.json`。

## 三条硬约束（写在 ERB 注释里，改这块前先读）

1. **宿主节点必须渲染在 `#eln-res-center` 外面。**
   若交给 Vue3 用 `v-if` 异步渲染，原生 pack 执行那一刻 `document.querySelector('#repositoriesTable')`
   返回 `null` → `mountWithTurbolinks` 抛错 → 整包挂掉。

2. **两个 `<script>` 都必须排在宿主节点之后，且 `eln_res_center.js` 在前。**
   浏览器按解析顺序**同步**执行脚本。`eln_res_center.js` 一跑，Vue `setup()` 里
   `watch(..., { immediate: true })` 立刻 `getElementById('#eln-repositories-native')`——
   那一刻该节点必须**已经解析完**。顺序写反的后果：首屏与深链 `?tab=inventory` 的台账是**空的**，
   而且**只有手动切一次页签才恢复**（`watch` 触发才补上 display）。这是本轮实际踩到的坑，
   现由护栏 `_verify_res_center.js` A2-3 断言钉死。

3. **显隐不归 Vue3 管。**
   那块 DOM 归原生 Vue app 所有；Vue3 只能切**外层容器**的 `style.display`
   （`ResCenter.vue#syncNativeRepoHost`）。宿主默认 `display:none`，页签真值仍只在
   Vue3 一处（`activeTab`）——**视图里不重算 `?tab=`**，否则两处真源。

## 附带决策

- **active/archived 切换会整页跳回 `/repositories`**：归档视图在 eln_ui 路由下没有实现，
  与其画一个假的归档筛选，不如让它走原生那条真路。
- **卡片网格保留在 `v-if="!embedded"`**：仅供原型离线独立跑（无宿主、无原生列表）。
  真机**绝不**显示 mock 台账——真值唯一。
- **高度覆写**：原生 `.fixed-content-body` 的高度算式是「原生整页」语境
  （`calc(100vh - header - navbar)`），放在资源中心（上方已有面包屑+页头+页签）会多出一条滚动条。
  只改高度，其余一律不动——复用的是原生组件，不是重画一张表。
- **零后端 Ruby 改动**：`payload.inventory.repositories` 保留（原型离线演示用）。

## 被否掉的两个方案

| 方案 | 否掉的理由 |
|---|---|
| 页签内留入口、整页跳 `/repositories` | 最稳，但离开资源中心上下文，与「内嵌」诉求不符 |
| 点页签即自动跳 `/repositories` | 同上，且点击即离开，返回只能靠浏览器后退 |
