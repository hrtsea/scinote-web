# ADR-0031：资源台账内嵌原生 Inventories 列表（不新造外壳）

- 状态：**部分被取代（2026-10-09）** —— 核心决策「用原生列表、不新造外壳」仍有效；
  实现方式被 **V2.0「换承载」**取代（见文末），以下「三条硬约束」**全部作废**。
- 决策人：用户（AskUserQuestion 三选一：整页跳转 / 点页签即跳 / **页签内嵌原生列表组件**）
- 相关：DEC-012（自研能力挂载到原生视图，不新造外壳）、`REQ-RESOURCE` / `SCN-RES-1`、`REQ-RES-APPROVER`、
  **ADR-0034**（Vue 化正路：源码归 addon、构建挂宿主 webpack）
- 影响面：`addons/eln_ui/app/views/scinote/eln_ui/res_center/index.html.erb`、
  `addons/eln_ui/app/javascript/vue/eln/views/ResCenter.vue`、`res_center_controller.rb`、`config/webpack/webpack.config.js`

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

> ⚠️ **2026-10-09 已全部作废**（V2.0 换承载删掉了它们所依附的机制）。原样保留供追溯。

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

---

## V2.0 换承载（2026-10-09，取代上面三条硬约束）

- 状态：已采纳
- 决策人：用户（AskUserQuestion 三选一：全部重写 / **保留原生能力，只换承载** / 保持现状）
- 相关：ADR-0034（Vue 化正路）、`rescenter-internals §8`
- 影响面：`ResCenter.vue`、`index.html.erb`、`res_center_controller.rb`、`config/webpack/webpack.config.js`
- 归档：`patches/2026-10-09-rc-inventory-host-swap/`（含部署配方 + 验收探针 + 实录）

### 决策

**保留原生能力，只换承载**：由 ResCenter 自己的 Vue app 直接
`import RepositoriesTable from 'host/repositories/table.vue'` 渲染，
不再渲染 `<repositories-table>` 自定义元素、不再加载 `vue_repositories_table` pack。

同一组件、同一批接口、同一份源码 —— 原生功能（新建库存 / 归档切换 / 列自定义 / 行操作 / 授权 / 导出）
零损失，而页面从「两个 Vue app + 挂载点外渲染 + `style.display` 显隐」收敛为**一个 Vue app**。

### 为什么三条硬约束可以作废

它们全部是「第二个 Vue app + `mountWithTurbolinks` 的 `innerHTML`-当-模板语义」的副作用：

| 原约束 | 作废原因 |
|---|---|
| 宿主节点必须在挂载点外 | 不再有第二个 app/pack，没有 `mountWithTurbolinks` 挂载点，组件是 `import` 进来的 SFC |
| 两个 script 顺序敏感 | 只剩一个 bundle，顺序无从谈起 |
| 显隐不归 Vue3 管 | 组件就在 Vue 模板里，`v-if="activeTab==='inventory'"` 天然管得到 |

### 代价与配套（必须一并做，否则功能静默缺失）

- URL / 权限仍**必须服务端生成**（前端不拼路由）：controller 新增 `native_repository_props`，
  并入 payload `inventory.native`。补上了原生 ERB 漏传的 required prop `userRolesUrl`。
- addon 入口必须补 `app.component('PerfectScrollbar', …)`：原生 `shared/access_modal/*` 模板用
  `<perfect-scrollbar>` 但**组件自身没有 import**，靠全局注册 —— 否则授权弹窗渲染失败。
- webpack 新增 `host` 别名 → `app/javascript/vue`（addon 要引用**非 `shared/` 子目录**的宿主组件）。

### 🔴 本轮踩到的坑：`isolate_namespace` 让 addon controller 的宿主路由助手全部失效

第一版 `native_repository_props` 用裸 `repositories_path(format: :json)`，`/eln_res_center` 直接 500：

```
ActionController::UrlGenerationError
  (No route matches {action: "index", controller: "repositories", format: :json})
```

根因（容器内探针实证）：`addons/eln_ui/lib/scinote/eln_ui/engine.rb` 有
`isolate_namespace Scinote::ElnUi` ⇒ Rails 把该命名空间下 controller 的 `_routes` 指向
**引擎自己的路由集**，而 eln_ui 引擎**没有 `config/routes.rb`（0 条路由）**：

```
ENGINE_ISOLATED=true   ENGINE_ROUTE_COUNT=0
CTRL_ROUTES_IS_ENGINE=true   CTRL_ROUTES_IS_APP=false
ENGINE_HAS_repositories_path=false   APP_HAS_repositories_path=true（rails runner 里正常）
```

于是裸调 = `engine.routes.generate(controller: "repositories", action: "index", …)` ⇒ 必然 `No route matches`。

**修法**：addon 里凡引用宿主路由，一律 `Rails.application.routes.url_helpers.<helper>`
（本 controller 收敛为私有 `host_routes`）。

> ⚠️ 与 ADR-0035 记的 **不是同一类**：那里是「该 helper 压根不存在（`user_settings_path` 无 collection 路由）
> ⇒ `NameError`」，runner 里同样失败；这里是「helper 存在于**宿主** route set，但 controller 的 `_routes`
> 是**引擎**那个 ⇒ `UrlGenerationError`」，runner 里**却正常**。两者都要全限定，但症状与排查方向相反：
> **controller 里炸、runner 里好 → 先怀疑 route set，不是参数。**

### 验收

`_prod_shots/_rc_native_inv_shot.js`：`FAILS=0 / ERRORS_TOTAL=0`，核心断言 `insideMount=true`
（原生表在 `#eln-res-center` **内部**）、旧容器 `#eln-repositories-native` 与旧挂载点 `#repositoriesTable`
均不存在、`pageVScroll=false`（原「多一条滚动条」问题上文 `高度覆写` 一节已随之消解）、
`New inventory` 在、授权弹窗 PerfectScrollbar 正常、其余 4 页签与原生 `/repositories` 页无回归。
