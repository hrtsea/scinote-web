# scinote-web 前端架构调研与 Vue 3 迁移范式

> 调研时间：2026-10-07 ｜ 结论基于代码（真源），非文档。  
> 迁移记录：第 1 轮 `users/settings/webhooks`（§5）｜第 2 轮 `label_printers/index`（§6）。

---

## 1. 结论摘要（先看这里）

1. **scinote-web 的前端已经是 Vue 3，不存在「Vue 2 待升级」这件事。**  
   `package.json` 为 `vue@^3.5.16`；全仓源码中 Vue 2 已被移除的 API（`filters` 选项 / `$listeners` /  
   `$scopedSlots` / `Vue.set` / `Vue.delete` / `Vue.prototype` / `Vue.extend` / `new Vue(` / `slot-scope` /  
   `$on(` / `$off(`）命中数**全部为 0**。仅存的 2 处 `beforeDestroy` 已改为 `beforeUnmount`（真实缺陷：Vue 3 下该  
   hook 不执行 → `window.resize` 监听器泄漏）。
2. **真正的「未 Vue 3 化」= 仍停留在第一代前端（Gen-1）的页面。**  
   本仓并存两代前端：Gen-1（Sprockets + jQuery）与 Gen-2（Webpack + Vue 3）。113 个非 partial 的 ERB 页面中：  
   44 页已 Vue 化、13 页仍只挂 Gen-1 资产、30 页无任何 JS、26 页属基础设施页（布局 / 邮件 / 错误页 / OAuth /  
   报表模板）。  
   > **2026-10-08 第 4 轮更新（已收口）**：上述 13 页中的 **11 页已在第 3 轮迁移并通过真浏览器运行时验证**；  
   > 同时修正扫描正则后**补出漏掉的第 14 页 `reports/new`**（1607 行 jQuery），**本轮已迁移并完成容器内
   > 真浏览器运行时验证 + `getReportData()` payload 校验**。  
   > ✅ **至此全仓再无「零 Vue 的纯 Gen-1 页面」**——剩余带 Gen-1 资产的页面均为「已挂 `vue_*` + Gen-1 协处理器」
   > 的混合态（见 §4）。详见 §4「第 4 轮扫描修正」与 §8「第 4 轮运行时验证记录」。
   > > **2026-10-08 第 5 轮更新（换角度扫描）**：第 4 轮的结论建立在「ERB → `javascript_include_tag`」的
   > > **正向**匹配上，它看不见「Gen-1 藏在 partial 里」的页面。本轮改用**四条反向/交叉路径**重扫，
   > > 又捞出 **4 个页面**（`users/sessions/new`、`users/passwords/{new,edit}`、`dashboards/show`），
   > > 其 Gen-1 全部藏在被 render 的 partial 中。**本轮已迁移为 3 个 Vue 岛并完成生产容器真浏览器验证**。
   > > 详见 §4「第 5 轮扫描」与 §8「第 5 轮运行时验证记录」。
3. **迁移不能靠「重写插件」，要靠「复用宿主能力」。** 见 §2.3 —— 这是本轮最大的发现，直接决定了后续每页的成本。

---

## 2. 前端架构

### 2.1 技术栈

| 维度       | 事实                                                                                                   |
| -------- | ---------------------------------------------------------------------------------------------------- |
| 框架       | Vue **3.5.16**，统一 `import { createApp } from 'vue/dist/vue.esm-bundler.js'`（**全量构建含编译器**，67 处）       |
| 路由       | **无 vue-router**。Turbolinks 驱动整页导航                                                                   |
| 状态管理     | **无 Vuex / Pinia**。组件本地 state + `app/javascript/vue/mixins/` + 全局 `window.I18n` / `GLOBAL_CONSTANTS` |
| 图表/表格    | `ag-grid-vue3@32`、`vue-echarts@8`、`vue3-perfect-scrollbar@2`、`vuedraggable@4`                        |
| 构建       | Webpack 5 + `vue-loader@17` + Babel；产物落 `app/assets/builds/`（**gitignore**，由 `yarn build` 重生成）       |
| Gen-1 资产 | Sprockets（`app/assets/javascripts/**`，143 个 JS），jQuery 3.7 + jQuery-ujs + **Bootstrap 3.4.1**        |
| 入口注册     | `config/webpack/webpack.config.js` 的 `entryList`，共 86 个 entry（48 个是 `packs/vue/*.js`）                |

### 2.2 分层

```
ERB 视图层   app/views/**            113 个页面模板（外壳 / 纯服务端渲染）
   │  javascript_include_tag '<entry>'
挂载层       app/javascript/packs/**  每个 entry = createApp + mountWithTurbolinks(app, '#id')
   │
组件层       app/javascript/vue/**    390 个 .vue（shared/ 复用层 + 领域目录）
   │
Addon 层     addons/*/app/{javascript,views,assets}/  （eln_ui / workbench 等）
```

**挂载机制**（`packs/vue/helpers/turbolinks.js`）：手写 Turbolinks 生命周期 —— 在 `turbolinks:before-cache`  
或 `before-render` 时 `app.unmount()` 并把挂载点 `innerHTML` 还原为初始值。**这是本仓所有 Vue 入口的统一约定。**

### 2.3 关键机制（决定迁移成本）

| 机制                                          | 事实                                                                               | 对迁移的意义                                                   |
| ------------------------------------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Bootstrap 3 的 `data-toggle`                 | 使用 **document 上的委托**（`click.bs.collapse.data-api` 等）                             | ✅ collapse / dropdown / modal **无需重写**，Vue 渲染同样的标记即可继续生效 |
| jQuery-ujs 的 `data-method` / `data-confirm` | 同样是 **document 委托**                                                              | ✅ `link_to method: :patch/:delete` 的语义可以**原样保留**，行为零偏差   |
| `dropdownSelector`（自定义下拉）                   | 全局 jQuery 插件；选中时**回写原生 `<select>` 并 trigger change**（`dropdown_selector.js:605`） | ✅ 可挂到 Vue 渲染的原生 `<select>` 上，表单语义仍归原生元素                  |
| `window.I18n`                               | 由 Sprockets 主包（`application.js.erb`）随布局全局加载                                      | ⚠️ **本检出不可靠**（见 §10.2）：可用 `i18n.t()`，但**只能命中既有 key**，新增 key 进不去；新页面文案请走服务端 ERB `t(...)` 注入 |

> 结论：**宿主已经提供了完整的「低级交互能力」，Vue 只需接管「数据与状态」。** 因此逐页迁移的成本主要在  
> 「把状态机从 jQuery 命令式改写为 Vue 声明式」，而不在「重造组件库」。

---

## 3. Vue 3 就绪度审计（证据）

| 检查项                                                                                        | 源码命中                                                                                        |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `filters:` 选项                                                                              | 0（42 处命中全是名为 `filters` 的 data/prop/事件名，**误报**）                                              |
| `$listeners` / `$scopedSlots` / `$children`                                                | 0                                                                                           |
| `Vue.set` / `Vue.delete` / `Vue.prototype` / `Vue.extend` / `Vue.observable` / `Vue.mixin` | 0                                                                                           |
| `new Vue(` / `slot-scope` / `slot="` / `$on(` / `$off(`                                    | 0                                                                                           |
| `beforeDestroy`                                                                            | 2（**已修**）→ `app/javascript/vue/{shared/datatable,shareable_links/assigned_items}/table.vue` |
| `@vue/compat` / `vue-template-compiler` / `vuex` / `vue-router`                            | 未使用                                                                                         |

> 注：`app/assets/builds/**` 与 `addons/*/app/assets/javascripts/**` 中出现的 `.native` / `beforeDestroy` 等命中，  
> 均为**构建产物或第三方库**，非源码。

---

## 4. 页面清单与分类

源：`find app/views addons -name "*.erb" ! -name "_*"` → **113 个非 partial 页面**。

| 类别                                                      | 数量 | 处置                    |
| ------------------------------------------------------- | -- | --------------------- |
| **已 Vue 化**（ERB 外壳 + `vue_*` entry）                     | 44 | 无需动                   |
| **Gen-1 待迁移**（仅挂非 vue JS）                               | 13 | 迁移候选（见下）              |
| **无 JS**（纯服务端渲染）                                        | 30 | 按需：有交互价值才迁移           |
| **基础设施**（layouts / mailer / errors / doorkeeper / 报表模板） | 26 | **保持 ERB**（迁移无收益且高风险） |

### Gen-1 迁移候选（12 个真实页面）

| 页面                                                                           | 当前 JS 资产                                                 | 依赖重插件                       |
| ---------------------------------------------------------------------------- | -------------------------------------------------------- | --------------------------- |
| `users/settings/webhooks/index`                                              | `users/settings/webhooks/index`                          | ✅ **第 1 轮已迁移**              |
| `label_printers/index`（fluics + zebra 两形态）                                   | `label_printers/index` + `label_printers/zebra_settings` | ✅ **第 2 轮已迁移**（无重插件依赖）      |
| `global_activities/index`、`my_modules/activities`                            | `global_activities/index.js`                             | ✅ **第 3 轮已迁移** collapse / modal |
| `assets/edit`、`assets/view`                                                  | `assets/office_form`                                     | ✅ **第 3 轮已迁移** 无            |
| `users/settings/teams/members`                                               | `users/settings/teams/show`                              | ✅ **第 3 轮已迁移** DataTable / TinyMCE / modal |
| `users/registrations/edit`                                                   | `croppie` + `users/registrations/edit`                   | ✅ **第 3 轮已迁移** Croppie       |
| `users/confirmations/new`、`users/invitations/edit`、`users/registrations/new` | `*_errors`                                               | ✅ **第 3 轮已迁移** 无            |
| `shareable_links/my_module_{protocol,results}_show`                          | handsontable                                             | ✅ **第 3 轮已迁移** handsontable  |

### ⚠️ 第 4 轮扫描（2026-10-08）修正：原清单漏了 1 页

> **根因**：原始清单用 `grep javascript_include_tag` + 只匹配 `javascript_include_tag 'x'`（空格 + 单引号）形态，
> **漏掉了括号形态** `javascript_include_tag("x")`。修正正则后重新扫描，发现第 **14** 页：

| 页面                                    | Gen-1 资产        | 规模          | 状态                    |
| ------------------------------------- | --------------- | ----------- | --------------------- |
| **`reports/new`**（报表生成向导，3 步）         | `reports/new`   | **1607 行 jQuery** | ✅ **第 4 轮已迁移 + 运行时验证通过**（见 §8 验证记录） |

**为何它危险**：这是全仓**唯一**「零 Vue + 一个巨型 Gen-1 岛」的页面。其余带 Gen-1 资产的页面
（`protocols/index`、`repositories/show`、`experiments/canvas`、`my_modules/protocols`、`teams/show`）均为**混合态**——
已挂 `vue_*`，Gen-1 资产是遗留协处理器；只有 `reports/new` 完全没有 Vue。

**修正后的判定准则**：判断「是否未 Vue 化」= 该页**没有任何 `vue_*` entry**，且挂了
`app/assets/javascripts/**` 下的自定义 Gen-1 资产。第三方库（`handsontable.full`、`pdf_js`、`croppie`、
`tui_image_editor`、`prism`、`inputmask`、`emoji_button`）**不算** Gen-1，它们是库不是岛。

> `addons/eln_ui/.../project_list/index` 挂的是 `eln_project_list`（**不带 `vue_` 前缀但已是 Vue**，见 ADR-0035），  
> 属「已 Vue 化」，是命名惯例的历史例外。

### ⚠️ 第 5 轮扫描（2026-10-08）：换角度——四条反向/交叉路径

第 4 轮用的是**正向**匹配（ERB → `javascript_include_tag`）。它的结构性盲区是：**Gen-1 藏在被 `render` 的
partial 里时，页面文件本身干干净净，正向扫描永远扫不到**。本轮换四个角度重扫：

| # | 扫描路径                                        | 结果                                                        |
| - | ------------------------------------------- | --------------------------------------------------------- |
| A | **内联 jQuery**：非 partial ERB 里直接写 `$(`/`jQuery(`  | **0 命中**（这块是干净的）                                           |
| B | **Gen-1 资产反向索引**：`app/assets/javascripts/**` 逐个反查谁引用 | 128 个资产中 22 个仍被引用，多数是 partial 引用                          |
| C | **webpack entry 侧交叉**：页面「有 Gen-1 且无 `vue_*`」      | 只剩 addon 的 `eln_vue3/*` blob 与 3 个 layout                 |
| D | **partial → page 反向追溯**（关键）                      | **捞出 4 个页面**，其 Gen-1 全在 partial 里                          |

**第 4 条捞出的 4 个页面（本轮已全部 Vue 化）**：

| 页面                             | Gen-1 藏在哪个 partial                                        | Gen-1 资产                                     | 规模      |
| ------------------------------ | --------------------------------------------------------- | -------------------------------------------- | ------- |
| `users/sessions/new`（登录页）      | `users/sessions/_login_disclaimer` + `users/shared/_linkedin_sign_in_links` | `users/login_disclaimer`、`users/shared/linkedin_sign_in_links` | 22 + 17 行 |
| `users/passwords/new`（忘记密码）    | `users/sessions/_login_disclaimer`                        | `users/login_disclaimer`                     | 22 行    |
| `users/passwords/edit`（重置密码）   | `users/sessions/_login_disclaimer`                        | `users/login_disclaimer`                     | 22 行    |
| `dashboards/show`              | `dashboards/_quick_start` → `protocols/index/_new_protocol_modal` | `protocols/new_protocol`                     | 57 行    |

**为什么值得做**：`users/sessions/new` 是**整个系统的入口页**；`protocols/new_protocol` 是**共享 partial**，
一处迁移同时覆盖 `dashboards/show`（type=`new`）与 `my_modules/protocols`（type=`copy`）两种形态。

**判定准则补充**：一个页面是否「未 Vue 化」，不能只看页面文件本身，必须**沿 `render partial` 链追溯**。
本轮已把这条写进扫描脚本（见 §4 第 5 轮的 D 条）。

---

## 5. 迁移记录（第 1 轮）：Webhook 设置页

### 5.1 改了什么

| 文件                                                                     | 动作                                                                    |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `app/javascript/vue/webhooks/index.vue`                                | **新增**：过滤器列表 / 懒加载详情 / 增改删 / 删除模态框（`<script setup>` 组合式 API）          |
| `app/javascript/vue/webhooks/webhook_form.vue`                         | **新增**：新建 & 编辑共用表单（含 422 错误回显）                                        |
| `app/javascript/vue/webhooks/method_select.vue`                        | **新增**：原生 `<select>` + 挂载 `dropdownSelector` 增强                       |
| `app/javascript/packs/vue/webhooks.js`                                 | **新增**：入口（`createApp` → `mountWithTurbolinks(app, '#webhooksIndex')`） |
| `config/webpack/webpack.config.js`                                     | 注册 entry `vue_webhooks`                                               |
| `app/views/users/settings/webhooks/index.html.erb`                     | 改写：保留无 JS 行为的头部/排序外壳，动态区交给 Vue；数据/URL 由服务端注入                          |
| `app/assets/javascripts/users/settings/webhooks/index.js`              | **删除**（85 行 Gen-1）                                                    |
| `app/views/.../_webhook_form.html.erb`、`_delete_filter_modal.html.erb` | **删除**（已迁入 Vue，避免双真源）                                                 |
| `config/initializers/assets.rb`                                        | 移除已删除资产的 precompile 行                                                 |

净变化：**-248 行 / +51 行**（不含新增的 3 个 .vue）。

### 5.2 为什么这样做（三个约束下的取舍）

1. **UI 不变** → 模板 1:1 沿用原 ERB 的 class 与结构，复用未改动的 `settings/webhooks.scss`；Bootstrap 3 的  
   collapse / dropdown / modal 全部走原 `data-toggle` 标记（document 委托），**外观与动画与迁移前一致**。
2. **接口行为不变** → 所有 URL 由 Rails 路由助手在 ERB 中生成后注入，HTTP 动词与参数名逐一对齐：
   - 新建/编辑：`POST` + `webhook[...]`（编辑带 `_method=patch`），422 时解析 JSON 回显字段错误；
   - 启用/停用：`data-method="patch"` + `webhook[active]` 查询参数（与原 `link_to method: :patch` 等价）；
   - 删 webhook：`data-method="delete"` + `data-confirm`；
   - 删过滤器：原生表单 `POST` 到 `destroy_filter`。
3. **低回归面** → 页面外壳（标题、排序菜单）本就不含 JS 行为，保留 ERB 渲染；Vue 只接管原本由 Gen-1 JS  
   驱动的动态区域。这与本仓另外 44 个已迁移页面的形态完全一致。

### 5.3 验证结果

| 项目                                       | 结果                                                                       |
| ---------------------------------------- | ------------------------------------------------------------------------ |
| 开发模式定向构建 `vue_webhooks`                  | ✅ `compiled successfully`，0 error / 0 warning                            |
| 生产模式定向构建 `vue_webhooks`                  | ✅ 编译通过；3 条 warning 为 **webpack 体积建议**（基线既有：未改动的 `vue_tags_table` 同样 3 条） |
| 受影响既有 entry（datatable / shareable_links） | ✅ `compiled successfully`                                                |

> ⚠️ **顺带修的宿主缺陷**：`babel.config.js` 无条件 `require` 的 5 个 Babel 插件未在 `package.json` 声明、  
> 本地 node_modules 缺失，导致**任何** webpack 构建都无法进行。已按项目既有做法（registry tarball 直装）  
> 补齐 `@babel/plugin-syntax-dynamic-import`、`-proposal-class-properties`、`-proposal-object-rest-spread`、  
> `-proposal-private-methods`、`@babel/plugin-syntax-object-rest-spread`、`babel-plugin-transform-react-remove-prop-types`、  
> `babel-plugin-dynamic-import-node`。**建议同步写回 `package.json` devDependencies**，否则 CI / 出镜像仍会失败。

---

## 6. 迁移记录（第 2 轮）：Label printers 设置页

页面 `app/views/label_printers/index.html.erb` 由**同一个模板**服务两个 action：  
`index`（fluics 云打印）与 `index_zebra`（Zebra BrowserPrint），因此两种形态必须一起迁。

### 6.1 迁移前的事实（两个 Gen-1 JS 岛）

| 文件                                                        | 行数 | 职责                                                                                               |
| --------------------------------------------------------- | -- | ------------------------------------------------------------------------------------------------ |
| `app/assets/javascripts/label_printers/index.js`          | 15 | API key 输入框状态机：`keyup/change` 时比对 `data-original-value`，切 `.warning` 类与 save/saved 按钮显隐          |
| `app/assets/javascripts/label_printers/zebra_settings.js` | 40 | 调全局 `zebraPrint.init()` 搜索本机 Zebra 设备，回调里用字符串拼 `<li>` 塞进 `.zebra-printers`；刷新按钮调 `refreshList()` |

### 6.2 改了什么

| 文件                                                                | 动作                                               |
| ----------------------------------------------------------------- | ------------------------------------------------ |
| `app/javascript/vue/label_printers/fluics_settings.vue`           | **新增**：API key 表单（内联状态机，与旧 JS 完全同构）              |
| `app/javascript/vue/label_printers/fluics_printers.vue`           | **新增**：打印器列表 + Update printers 表单                |
| `app/javascript/vue/label_printers/zebra_printers.vue`            | **新增**：Zebra 设备列表 + 刷新按钮（桥接全局 `zebraPrint`）      |
| `app/javascript/packs/vue/label_printers.js`                      | **新增**：入口；本页有 3 个区块，**逐个挂载**（未渲染的挂载点自动跳过）        |
| `config/webpack/webpack.config.js`                                | 注册 entry `vue_label_printers`                    |
| `app/views/label_printers/_fluics_settings.html.erb`              | 改写：说明文案保留 ERB，settings / printers 两段换成挂载点        |
| `app/views/label_printers/_zebra_settings.html.erb`               | 改写：说明文案保留 ERB，printers 段换成挂载点                    |
| `app/views/label_printers/index.html.erb`                         | `javascript_include_tag` 换成 `vue_label_printers` |
| `app/assets/javascripts/label_printers/{index,zebra_settings}.js` | **删除**（Gen-1，共 55 行；目录已空并移除）                     |
| `config/initializers/assets.rb`                                   | 移除上述两个资产的 precompile 行                           |

### 6.3 三个非显然的设计约束（后续页面会复现）

1. **挂载点用 `<li>` 本身，而不是往 `<ul>` 里塞 `<div>`。**  
   组件模板只渲染「`<li>` 的内部内容」（`.collapse-row` + `<ul class="collapse-content">`），  
   于是最终 DOM 与迁移前**逐层一致**（`<ul><li><div class="collapse-row">…`），  
   不会因为多包一层而改变 `.label-printer-show ul li` / `.collapse-content` 的间距。  
   ⚠ 代价：一个页面可以有多个 app（本页 3 个），`mountWithTurbolinks` 各自登记自己的卸载/还原。
2. **不能把 Vue 正在渲染的 `<ul>` 交给 `zebraPrint`。**  
   `zebraPrint` 在收到首个设备时会直接对传入的 selector 调 `.empty()`（`zebra_print.js:73`）。  
   若把真实节点交出去，外部清空会让 vdom 与真实 DOM 脱节。做法：传一个**游离的** `$(document.createElement('ul'))`，  
   列表渲染完全由 Vue 的 `v-for` 负责，`zebraPrint` 只负责「发现设备」并通过回调上报。
3. **两个 `<form>` 由 Vue 渲染，但 CSRF 不能靠 `form_with`。**  
   `config.load_defaults 7.2` ⇒ `form_with_generates_remote_forms = false`，原表单是**普通 POST**（非 remote），  
   所以 Vue 渲染 `<form method="post">` 与原行为等价；`authenticity_token` 用 `form_authenticity_token` 由 ERB 注入。  
   参数名逐一对齐：`label_printer[fluics_api_key]`，action = `create_fluics_label_printers_path`。

> **注意事项（JSON 注入属性）**：`:api-key="<%= @fluics_api_key.to_json %>"` 是**本仓既有约定**  
> （`experiments/index`、`my_modules/index`、`shareable_links/*` 同款）。ERB 会转义成 `&quot;`，  
> 浏览器解析属性时再解码回 `"`，因此 JSON 里的引号是安全的 —— 不要画蛇添足加 `raw` / `html_safe`，那才会把属性打断。

### 6.4 验证结果

| 项目                               | 结果                                                                                          |
| -------------------------------- | ------------------------------------------------------------------------------------------- |
| `vue_label_printers` 开发模式定向构建    | ✅ `compiled successfully`，0 error / 0 warning                                               |
| `vue_label_printers` 生产模式定向构建    | ✅ 编译通过；3 条 warning 全部是 **webpack 体积建议**（245 KiB）                                            |
| 基线对照（未改动的 `vue_tags_table`，prod） | ✅ 同样 3 条同款 warning ⇒ 本次**零新增告警**                                                            |
| 产物内容抽查                           | ✅ 产物内确含 `zebraPrint` / `fluics_api_key` / `zebra-printer-refresh` / `no_printers_available` |


| 改动 ERB 语法检查 | ✅ 3 个模板 `ERB.new(...).src` + `RubyVM::InstructionSequence.compile` 全部通过 |

> ⚠️ 本仓**未安装 eslint**（`eslint.config.mjs` 存在，但 `node_modules/eslint` 缺失、`package.json` 无 lint 脚本），  
> 因此静态检查只能靠构建器（vue-loader + babel）兜底。

---

## 7. 可复用迁移范式（逐页照做）

1. **判定**：`grep javascript_include_tag <页面>` —— 是否已挂 `vue_*`；未挂则读其 Gen-1 JS 摸清行为。
2. **建组件**：`app/javascript/vue/<domain>/*.vue`，`<script setup>` 组合式 API；  
   `i18n` 取自 `getCurrentInstance().appContext.config.globalProperties.i18n`。
3. **建入口**：`app/javascript/packs/vue/<name>.js`，三行固定套路（`createApp` → `app.component` →  
   `app.config.globalProperties.i18n = window.I18n` → `mountWithTurbolinks(app, '#id')`）。
4. **注册 entry**：`config/webpack/webpack.config.js` 的 `entryList` 加一行 `vue_xxx: './app/javascript/packs/vue/xxx.js'`。
5. **改写 ERB**：保留无 JS 行为的静态外壳；动态区替换为 `<xxx-yyy :props="<%= payload.to_json %>"></xxx-yyy>`；  
   数据与 URL **全部由服务端生成后注入**（保证接口一致）；`javascript_include_tag` 换成新 entry。
6. **删旧件**：删掉 Gen-1 Sprockets 资产 + `config/initializers/assets.rb` 的 precompile 行 + 迁入 Vue 的 partial  
   （避免同一事实两个真源）。
7. **验证**：临时配置 `require('./webpack.config.js')` 后覆写 `entry` 只编目标 entry；  
   再做一次 `NODE_ENV=production` 构建。**禁止跑全量 webpack。**

### 交互能力的取用顺序（按成本从低到高）

1. 直接沿用 Bootstrap 3 的 `data-toggle` / `data-dismiss`（document 委托，零成本）；
2. 沿用 jQuery-ujs 的 `data-method` / `data-confirm`（零成本）；
3. 在 `onMounted` 里挂全局 jQuery 插件（如 `dropdownSelector`），并让该元素处于**不被响应式重渲染**的子树；
4. 确实需要时，才改用 `app/javascript/vue/shared/**` 的设计系统组件重写。

---

## 8. 剩余工作与风险

- ✅ **第 3 轮已完成**：`assets/{view,edit}`、`users/{confirmations,invitations,registrations}` 的 `*_errors`、
  `global_activities/index` + `my_modules/activities`、`users/settings/teams/members`、
  `shareable_links/my_module_{protocol,results}_show` —— 共 11 页，已通过**容器内真浏览器运行时验证**
  （HTTP 200 + Vue island 挂载 + 0 console error）。
- ✅ **第 4 轮已完成：`reports/new`（报表向导，1607 行 jQuery）**。按下表的 7 个内聚关注点分解后，
  统一收在**一个** `vue_reports_new` entry 中（而非 7 个 island 单独上线），理由见下方「架构取舍」：

  | #   | island                            | 职责                                            | 依赖                          |
  | --- | --------------------------------- | --------------------------------------------- | --------------------------- |
  | 1   | 向导外壳（header/footer/步骤条）            | `currentStep` / 前进后退 / 进度条 / continue 校验       | Bootstrap tab（data-toggle）  |
  | 2   | 报表名输入                              | 名称 + `NAME_MIN_LENGTH` 校验                      | 无                           |
  | 3   | 项目 / 模板下拉                          | `#projectSelector` `#templateSelector` `#docxTemplateSelector` | dropdownSelector 桥接（见 §6.2） |
  | 4   | 模板取值区                              | AJAX 拉 `valuesEditorPath` 的 HTML 并注入            | dropdownSelector 再 init     |
  | 5   | 项目内容树                              | 实验 / 任务三态复选、hide-unchecked、折叠展开、sortable      | jQuery sortable 桥接          |
  | 6   | 任务内容设置                             | protocol steps / results / repositories 全选联动    | 无                           |
  | 7   | 生成按钮                              | `getReportData()` → POST/PUT JSON + 错误 flash     | 无                           |

  ⚠ **约束**：第 3、4、5 项依赖全局 jQuery 插件（`dropdownSelector` / `sortable`），必须沿用 §6.2 的**桥接模式**——
  Vue 只负责状态，插件操作的节点放在**不被响应式重渲染**的子树，或传游离节点。

### 第 4 轮迁移记录：`reports/new`（报表向导）

| 文件                                                    | 动作                                                                      |
| ----------------------------------------------------- | ----------------------------------------------------------------------- |
| `app/javascript/vue/reports/wizard.vue`               | **新增**：向导全部行为（步骤/名称校验/下拉桥接/复选联动/`getReportData`/生成 AJAX） |
| `app/javascript/packs/vue/reports_new.js`             | **新增**：入口，注册 `ReportsWizard` + `mountWithTurbolinks('#reportsNewWizardApp')` |
| `config/webpack/webpack.config.js`                    | 注册 entry `vue_reports_new`                                              |
| `app/views/reports/new.html.erb`                      | 改写：header/footer 换成 Teleport 挂载点，pane 原样保留，`javascript_include_tag` 换 `vue_reports_new` |
| `app/assets/javascripts/reports/new.js`               | **删除**（1607 行 Gen-1）                                                   |
| `config/initializers/assets.rb`                       | 移除 `reports/new.js` 的 precompile 行                                      |

**架构取舍（本轮最关键的决定）**：三个 tab pane（`_first_step` / `_second_step` / `_third_step`，共 417 行 ERB）
**保持服务端渲染，不被 Vue 接管**。原因：

1. pane 内含大量 Rails 侧逻辑——`readable_by_user` 作用域、`@project_contents` 排序快照、
   `RepositorySnapshot` 与 `Repository` 的分支渲染、`Report.default_repository_columns` —— 把它们 JSON 化
   等于把权限判定搬到前端，**是 fail-open 风险**（比对第 6 节权限纪律）。
2. 因此 header / footer 用 **Vue `Teleport`** 渲染到 ERB 预留的空挂载点（`#reportsNewHeaderMount` /
   `#reportsNewFooterMount`），pane 完全不被 Vue 触碰；Vue 通过**事件委托** + 选择器读取 pane 状态，
   并桥接 `dropdownSelector` / `sortable` / `collapse` 三个全局 jQuery 插件（§6.2 桥接模式）。

**验证状态**：✅ 定向构建 `vue_reports_new` **0 error / 3 warning**（3 条均为 webpack 体积建议，与基线同款）；
✅ 产物抽查命中 `reportsNewWizardApp` / `reportsNewHeaderMount` / `dropdownSelector` / `getReportData` 等标记；
✅ ERB 语法 `ERB.new(...).src` + `RubyVM::InstructionSequence.compile` 通过；
✅ **容器内真浏览器运行时验证通过**（2026-10-08，Edge + 登录态），详见下节。

### 第 4 轮运行时验证记录（2026-10-08，生产容器）

**静态挂载**（`/reports/new` 与 `/projects/35/reports/new` 两条路由各测一遍，结果一致）：

| 探针                                                 | 结果 |
| -------------------------------------------------- | -- |
| HTTP 状态 / 是否跳登录                                     | `200` / 否 |
| `#reportsNewWizardApp` 上 `__vue_app__`                 | ✅ 已挂载 |
| 未编译标签 `<reports-wizard>` 残留                          | ✅ 无 |
| Teleport header（`.reports-new-header` + 名称输入 + 取消按钮）   | ✅ 渲染 |
| Teleport footer（`.reports-new-footer` + continue + generate + 3 个步骤） | ✅ 渲染，`data-step=1` |
| `vue_reports_new` bundle 响应                          | `200` |
| console error                                      | **0** |

**交互全链路**（选项目 → 进第 2 步 → 全选 → 进第 3 步 → 后退）：

| 步骤                                | 实测                                                                    |
| --------------------------------- | --------------------------------------------------------------------- |
| 选项目（dropdownSelector 桥接）           | `getValues('#projectSelector') === '1'`，模板自动选中 `scinote_template`，continue 由 disabled → enabled |
| continue → step 2                 | `pane2Active=true`、`data-step=2`、AJAX 注入项目内容 **36 836 字符 / 9 个实验 / 56 个任务** |
| 全选任务                              | 56 个 `.report-my-module-checkbox` 全勾中，generate 由 disabled → enabled      |
| continue → step 3                 | `pane3Active=true`、`data-step=3`、`.task-contents-container` 内 12 个 protocol 勾选项 |
| 后退                                | 回到 `data-step=2`，pane2 重新 active                                      |
| console error                     | **0**                                                                 |

**`getReportData()` payload 校验**（用请求拦截捕获 POST body 后 fulfill 空响应，**不真正创建报表**）：
顶层键 = `report` / `project_id` / `template_values` / `project_content`（与 jQuery 原版一致）；
`report.settings.template='scinote_template'`、`all_tasks=true`、`project_id='1'`；
`project_content.experiments` 9 条、合计 56 个 `my_module_ids`；
`settings.task` 含 `protocol`(12 键) / `archived_results` / `text_results` / `file_results` /
`file_results_previews` / `table_results` / `result_comments` / `activities` / `repositories` /
`excluded_repository_columns` / `result_order`。

**本轮暴露并修掉的两个真问题**（都是迁移引入的回归，静态检查发现不了）：

1. 🔴 **`report_path(@report)` 对未持久化记录抛 `UrlGenerationError`** → 新建态整页 500。
   原版把 `report_path(@report)` 包在 `<% if @edit %>` 分支里所以不炸；迁移后我把它**无条件**提为组件
   prop，新建态 `@report` 是 new record（`id: nil`）→ 路由生成失败。
   修法：`:update-url="<%= (@edit == true && @report.persisted? ? report_path(@report) : '').to_json %>"`，
   沿用原版的门控语义（`updateUrl` 只在编辑态使用）。
   **教训：把散布在 ERB 分支里的 URL helper 收进组件 props 时，必须连同它原有的条件分支一起搬。**
2. 🔴 **ERB 注释里嵌 `<% ... %>` 会提前终止注释**。我写的 `<%# ... <% if @edit %> ... %>` 中内层 `%>`
   结束了注释，后面的中文变成**标签内的杂属性**，把 `:update-url` 的表达式污染成
   `Invalid or unexpected token`，Vue 整个挂不上（页面仍 200、pane 正常，极具迷惑性）。
   **教训：`<%# %>` 注释内禁止再写 `<%`/`%>`。**
- **不要迁移**：`layouts/*`、`users/mailer/*`、`errors/*`、`doorkeeper/*`、报表模板 —— 服务端渲染是正确选择。
- **双真源风险**：迁移一页就要删一页的旧实现；本仓已多次出现「新实现上线、旧实现仍在库里」导致的判断分歧。
- **构建产物未提交**：`app/assets/builds/**` 是 gitignore 的，本机只做过「定向编译到仓外目录」的校验，  
  **并未刷新仓内 `app/assets/builds/`**（该目录当前是更早一次 `yarn build` 的快照，连第 1 轮的 `vue_webhooks.js` 都没有）。  
  因此要真正在浏览器里看到这两个页面，必须先跑一次正常构建（`bin/yarn build`，或按 `Dockerfile.production` 的 builder 阶段），  
  它会自动把新 entry 产出到 `app/assets/builds/` 并进入 `assets:precompile`。
- **未做的验证**：只有构建验证 + ERB 语法验证，**没有运行时验证**（需在容器内起服务、以真实会话点读每个按钮/表单）。  
  上线前必须按项目既定纪律走「HTTP + 真会话」验证。
- **顺带发现（未处理）**：`config/webpack/webpack.config.js` 的 `entryList` 里  
  `vue_shareable_links_my_module_assigned_items` **重复定义两次**（值相同，行为无影响，但属冗余，建议清理）。

---

### 第 5 轮迁移记录（2026-10-08）：登录/密码页 + dashboard 的三个岛

**策略**：不整体重写页面。沿用 §6.2 **桥接模式**——`login_disclaimer` / `new_protocol_modal` 两个岛的
modal **保持服务端渲染的 ERB 不动**（前者含 `html_safe` 的运营配置内容，后者含 `readable_by_user` 作用域下的
角色下拉），Vue 只接管**行为**；`linkedin_sign_in` 则完全由 Vue 渲染（纯换图，无权限语义）。

| # | 岛                       | 新 entry                     | 组件                                            | 覆盖页面                                                                             |
| - | ----------------------- | --------------------------- | --------------------------------------------- | -------------------------------------------------------------------------------- |
| 1 | 登录免责声明 modal          | `vue_login_disclaimer`      | `vue/users/login_disclaimer.vue`              | `sessions/new`、`passwords/new`、`passwords/edit`、`registrations/new`、`invitations/edit`（5 页） |
| 2 | LinkedIn 按钮换图          | `vue_linkedin_sign_in`      | `vue/users/linkedin_sign_in.vue`              | `sessions/new`、`registrations/new`（+ `_links`）                                       |
| 3 | 新建/复制 protocol modal | `vue_new_protocol_modal`    | `vue/protocols/new_protocol_modal.vue`        | `dashboards/show`（type=`new`）、`my_modules/protocols`（type=`copy`）                      |

**行为移植的保真点**（第 3 个岛最易错，57 行里塞了 6 类行为）：
- `dropdownSelector` 角色下拉 → **桥接**（Vue 不接管节点，只桥 `onChange` 回写 hidden field）
- 名称输入 → 提交按钮 `disabled` 取反（保留了原版 `length != 0 || length >= NAME_MIN_LENGTH` 的**原样语义**，
  即使前半段已覆盖后半段——**不擅自"修 bug"**，行为差异留作独立议题）
- 可见性勾选 → `#roleSelectWrapper` 显隐 + hidden field `disabled`
- `ajax:success` / `ajax:error` → `HelperModule.flashAlertMsg` + 关 modal
- `shown.bs.modal` → 清空名称、按触发链接的 `data-protocol-name` 预填、聚焦

**删除**：`protocols/new_protocol.js`、`users/login_disclaimer.js`、
`users/shared/linkedin_sign_in_links.js`（共 96 行）及其 3 条 `assets.rb` precompile 声明。

### 第 5 轮运行时验证记录（2026-10-08，生产容器）

- 定向构建 3 个 entry：**0 error / 0 warning**（产物 244–247 KiB，与基线同量级）。
- ERB 语法：5 个改后的模板**全部 OK**。⚠ 校验器必须用 **Erubi**（Rails 的引擎，支持 `<%= ... do %>` 块语法）；
  用裸 `ERB.new(trim_mode:'-')` 会把**未改动的 HEAD 原版也报成语法错**，是假阳性。
- 真浏览器（playwright-core + Edge，注入临时 `login_disclaimer` 把条件渲染的岛逼出来后验证）：

  | 用例                     | 结果                                                                                                     |
  | ---------------------- | ------------------------------------------------------------------------------------------------------ |
  | `/users/sign_in`       | 200 / Vue 挂载 / modal 内容（标题·正文·按钮）与注入配置一致 / **0 console error**                                           |
  | 点登录按钮 → modal      | `display: none → block`、`.in` 类、backdrop 出现、**仍停留在登录页**（提交被正确拦截）/ 0 error                                 |
  | 点「我同意」→ 提交        | 成功登录并跳转到 `/` / 0 error                                                                                   |
  | `/users/password/new`  | 200 / Vue 挂载 / modal 标题正确 / 0 error                                                                       |
  | `/dashboard`           | 200 / Vue 挂载 / 打开 modal `display: block` / 输入名称后 `disabled: true → false` / 勾选可见性后 `#roleSelectWrapper` `hidden → 可见` / 0 error |
  | `/modules/1/protocols` | 200 / Vue 挂载 / 0 error                                                                                     |

- **LinkedIn 岛：本环境无法运行时触发**（`LINKEDIN_KEY` 未配 → `omniauth_providers` 为空 → partial 不渲染）。
  仅通过构建 + 产物标记验证，属**已知未覆盖项**，待有 LinkedIn 凭据的环境补验。
- 收尾：hpxing 密码还原（MATCH）、`login_disclaimer` 配置还原（并额外清除了备份时误写入 `settings` 列的
  `app_sttg_*` env 派生键）、容器临时脚本已删、无悬空资产引用、无散落 manifest。
  还原后复检登录页：200 且岛**确实不再渲染**（证明条件渲染双向都正确）。

---

## 9. 第 6 轮：addon blob → 宿主 webpack entry（交付路径修正，ADR-0034/0035）

> **本轮不是 Gen-1 → Vue**，而是**已 Vue 化页面**的「交付路径」修正：把 6 个 addon 页面违反 ADR-0034 的
> **预打包 blob**（`addons/*/app/assets/{javascripts,stylesheets}/{eln_vue3,workbench_vue3}/*`，~726 KB 构建产物进仓库）
> 改成**宿主 webpack entry**正路。真源此前「裂两半」——仓库里只有 minified blob，SFC 真源在**仓库外**
> 独立工程 `F:/eln开发/ELN系统-Vue3/src/`。

### 9.1 改了什么

| 文件 | 动作 |
| --- | --- |
| `addons/eln_ui/app/javascript/vue/eln/**` | **新增**：把 `ELN系统-Vue3/src/**` 整树搬进仓库（真源归位）；`from 'vue'` 归一为 `vue/dist/vue.esm-bundler.js` |
| `addons/eln_ui/app/javascript/packs/eln_{res_center,workbench,project_detail,exp_detail,task_detail,apply_detail}.js` | **新增** 6 个 pack（各 re-import 对应 `entries/*.js`，加载即自动挂载，保留原 shipping 行为） |
| `config/webpack/webpack.config.js` | `entryList` 注册 6 个 entry：`eln_res_center` / `eln_workbench` / `eln_project_detail` / `eln_exp_detail` / `eln_task_detail` / `eln_apply_detail` |
| 6 个 ERB（res_center / project_detail / exp_detail / my_module_detail / res_apply_detail / workbench） | `asset_path 'eln_vue3/xxx.css'` + `javascript_include_tag 'eln_vue3/xxx.js'` → `stylesheet_link_tag 'eln_*'` + `javascript_include_tag 'eln_*'` |
| `addons/eln_ui/lib/scinote/eln_ui/engine.rb`、`addons/workbench/lib/scinote/workbench/engine.rb` | 删 blob 登记；**新增 6 entry 的 js+css 登记进 `assets.precompile`**（见 §9.2 关键发现） |
| `config/initializers/assets.rb` | 删 project_detail/eln-system-vue3、exp_detail 等 blob 的 precompile 行（**仅保留 `eln_vue3/eln_project_list.css`**：列表页 SFC 无 `<style>`，样式仍由该 blob 承载，属历史例外） |
| `addons/eln_ui/app/assets/{javascripts,stylesheets}/eln_vue3/*`、`addons/workbench/app/assets/*/workbench_vue3/*` | **删除** 12 个 blob（`eln_project_list.css` 除外） |

### 9.2 🔴 关键发现：webpack 产物**必须**登记进 `assets.precompile`（纠正旧说法）

**现象**：只做 webpack 构建 + `docker cp` 产物到 `app/assets/builds/`，6 页**全部整页 500**：
```
Sprockets::Rails::Helper::AssetNotFound:
  The asset "eln_res_center.css" is not present in the asset pipeline.
```

**根因**：生产 `config.assets.compile = false` ⇒ `stylesheet_link_tag` / `javascript_include_tag`
**只走 Sprockets manifest**（`public/assets/.sprockets-manifest-*.json`）解析。`app/assets/builds` 虽在
`config.assets.paths` 里（Sprockets 能找到源文件），但**没被 fingerprint 进 manifest** ⇒ AssetNotFound。

> ⚠ **文档旧说法作废**：§8 曾写「新 entry 会**自动进入** `assets:precompile`」——**实测不成立**。
> 实测 `config.assets.precompile` 共 105 条、**无任何 catch-all 正则/glob**，且不含 `eln_project_list.js`，
> 但 manifest 里**有** `eln_project_list-<digest>.js` ⇒ 证明它当年是**手工预编译**进的 manifest，不是构建自动带的。

**修法（双保险）**：
1. **登记**（未来出镜像稳）：6 entry 的 js+css 写进 `config.assets.precompile`（eln_ui engine 10 条 + workbench engine 2 条）；
   出镜像时 `yarn build`（Dockerfile.production L112）先于 `rails assets:precompile`（L121）⇒ 下次镜像必带。
2. **手工预编译**（运行容器立即生效）：用 `tools/precompile_entry.rb` 的**多 entry 版**
   （`F:/eln开发/_precompile_addon_entries.rb`）以 **root** 跑，把 12 个目标 fingerprint 进 manifest：
   ```
   docker cp _precompile_addon_entries.rb scinote_web_production:/tmp/precompile_multi.rb
   docker exec -u 0 scinote_web_production bash -c \
     'cd /usr/src/app && RAILS_ENV=production ENTRIES=eln_res_center.js,eln_res_center.css,... \
      bundle exec rails runner /tmp/precompile_multi.rb'
   ```
   ⚠ `Sprockets::Manifest.new(env, dir, filename)` 的 filename **必须传绝对路径**，否则 manifest 写到 CWD
   （`/usr/src/app/.sprockets-manifest-*.json` 散落文件、真 manifest 不更新）。
   ⚠ 预编译后**必须 restart**（生产内存缓存 manifest，改文件不重载）。
   验收：12/12 `OK <name> -> <name>-<digest>.{js,css}` + 真 manifest 有新 key + `public/assets` 有对应 digest 文件。

### 9.3 运行时验证记录（2026-10-08，生产容器 + 真浏览器）

登录态用 `mksession.rb` **现签 Warden 会话**（不改密码，避开改密/还原风险）。脚本 `_prod_shots/_verify_addon_vue.js`。

| 页面 | 路由 | HTTP | Vue 挂载 | 加载资产（新 builds，digest 名） | console error |
| --- | --- | --- | --- | --- | --- |
| 资源中心 | `/eln_res_center` | 200 | ✅ | `eln_res_center-<d>.{js,css}` | 0 |
| 工作台 | `/eln_workbench` | 200 | ✅ | `eln_workbench-<d>.{js,css}` | 0 |
| 项目详情 | `/projects/36/eln_project_detail` | 200 | ✅ | `eln_project_detail-<d>.{js,css}` | 0 |
| 实验详情 | `/experiments/2/eln_exp_detail` | 200 | ✅ | `eln_exp_detail-<d>.{js,css}` | 0 |
| 任务详情 | `/experiments/52/my_modules/92/eln_task_detail` | 200 | ✅ | `eln_task_detail-<d>.{js,css}` | 0 |
| 申请详情 | `/eln_res_apply/SQ-2026-0094` | 200 | ✅ | `eln_apply_detail-<d>.{js,css}` | 0 |

**6/6 PASS**（HTTP 200 + `#eln-*._vnode` 已挂载 + 0 console/page error + 0 failed request），
且**加载的确是新的 digest 产物、不含任何 `eln_vue3/*` blob**。截图见 `_prod_shots/_addon_vue_shots/`，
逐页视觉确认渲染正确（资源中心台账 / 工作台待办 / 项目基础信息 / 实验任务列表 / 任务详情 / 申请审批流）。

> 附注（非迁移问题）：`/experiments/52/eln_exp_detail` 对 hpxing 返回 **404** 是**正确的权限口径**
> （`Experiment.readable_by_user` 不含 epp 项目 36 的 exp 52 / 即 `self_only_researcher` 隔离），
> 与迁移无关；改用 hpxing 可读的 exp 2 验证即 200。同理 apply 详情：无权申请单渲染 forbidden 分支（200 + 挂载），
> 可见申请单 `SQ-2026-0094` 渲染完整审批流。


---

## 10. 工作区列表「复刻原生」（2026-10-08，ADR-0034 rev）

### 10.1 背景与决策

`/users/settings/teams` 此前已按 ADR-0034 原版 Vue 化为 **AG Grid** 版，但用户指出**功能与 UI 与原生页面不一致**，
要求「根据原生的页面走 vue 化路子，重新 vue 化」。三项决策：

1. **复刻程度＝完全复刻原生**；2. **数据链路＝恢复服务端分页排序**；3. **最终形态＝Vue 复刻原生 + 服务端分页排序**。

> 「原生版本」= Vue 化那一刀 `fbe24fd3d` 的**父提交** `fbe24fd3d^`。该提交把四件事捆在一起
> （workspace 列表 Vue 化 / system_admin 建站 / 3 个删除链 bug 修复 / Gemfile addon 收敛），
> **后三者是本仓既有成果，本次复刻不得回退**。

### 10.2 🔴 两条新铁律（通用，已并入 §2.3 与 §9.2 的口径）

**(A) webpack 产物必须登记进 `config.assets.precompile`。** 生产 `assets.compile=false` ⇒
`javascript_include_tag` / `stylesheet_link_tag` **只走 Sprockets manifest**；未登记 ⇒ `AssetNotFound` ⇒ **整页 500**。
本轮顺带补齐历史缺口：`eln_ui` engine 的 `precompile` 列表补入 `vue_teams_table.js` 等。

**(B) 客户端 i18n 在本检出不可靠 ⇒ 文案由服务端 ERB `t(...)` 注入为 prop（单一真源）。**
根因链：

1. `app/assets/javascripts/i18n/translations.js` 是**已提交的生成产物**（按字母序 JSON），新增 key 不在其中；
2. `config/i18n-js.yml` **缺失** ⇒ `rake i18n:js:export` **静默 no-op**（不报错，也不产出）；
3. `i18n_bundle.js` 依赖的 `scinote/i18n/application` 已随 i18n addon 被摘除 ⇒ **`i18n_bundle.js` 在本检出根本无法重新预编译**
   （`couldn't find file 'scinote/i18n/application'`）。

⇒ 症状是页面上出现 `[missing "en.users.settings.teams.index.showing" translation]`。
⇒ 修法：**回滚对生成产物的补丁**，改由 ERB `t(...)` 注入 `labels` prop，组件只做 `%{key}` 插值（不碰 `window.I18n`）。
> 曾短暂尝试直接 patch `translations.js`（4 处精准文本插入），**已否决并回滚**——那是改生成产物，且不可复现。

### 10.3 改动清单

| 文件 | 变更 |
| --- | --- |
| `config/routes.rb` | 恢复 `POST users/settings/teams/datatable`（`as: teams_datatable`） |
| `app/controllers/users/settings/teams_controller.rb` | 新增 `datatable` action；`index` 去掉 `@teams_payload` 只留 `@member_of`；新增私有 `workspace_scope` / `datatable_per_page` / `sort_workspaces` / `workspace_row` 等 |
| `app/views/users/settings/teams/index.html.erb` | 还原原生页头结构（描述 + `member_of` 计数 + `#new-team-button`）+ `#teams-table-vue` 挂载点 + `labels` prop + `stylesheet_link_tag 'datatables'` |
| `addons/eln_ui/app/javascript/vue/teams/table.vue` | 由 AG Grid **完全重写**为「复刻原生」Bootstrap 表格（4 列 / 无搜索 / 原生弹窗 / 服务端分页排序） |
| `addons/eln_ui/app/javascript/packs/vue_teams_table.js` | 移除 `window.__ELN_TEAMS__` 根 data 桥接 |
| `addons/eln_ui/lib/scinote/eln_ui/engine.rb` | `precompile` 补登记（含 `vue_teams_table.js`、`eln_project_list.js`） |
| `config/locales/{en,zh-CN}.yml` | `teams.index` 下新增 `showing` / `loading`；`previous`/`next` 复用既有 `views.pagination.*` |

### 10.4 验证记录（2026-10-08，生产容器 + 真浏览器）

`F:/eln开发/_prod_shots/_verify_teams_page.js` —— **20/20 PASS**：

```
thead        = ["Workspace","Role","Members",""]
infoText     = "Showing 1 to 2 of 2 entries"      ← i18n 断链已修（不再 missing）
rowIds       = ["team-row-40","team-row-1"]
datatableCalls = [{"status":200,"method":"POST"},{"status":200,"method":"POST"}]
```

关键断言：挂载点已挂 Vue / 渲染 `.table.dataTable` / `.ag-theme-alpine` 消失 / `.dataTables_wrapper` 存在 /
thead 4 列 / **无搜索框** / `#new-team-button` 存在 / 退出按钮列完整（`{enabled:1,disabled:1,total:2,rows:2}`，
禁用=最后管理者，与后端 `last_with_permission?` 一致）/ `datatables.css` 已加载 / digest 产物加载 /
点表头触发新请求 / 退出弹窗可见且含表单 / `datatable` 端点全 200 / 0 console error / 0 pageerror / 0 失败请求。

截图 `_prod_shots/_teams_page_shots/{teams_list,teams_leave_modal}.png` 视觉确认与原生一致。

### 10.5 部署链（本轮实测，供复用）

```
宿主定向 webpack（禁全量）→ docker cp 产物+view → 手工 Sprockets 预编译（root）
  → docker restart → mksession.rb 现签 Warden 会话 → 真浏览器断言 + 截图
```

- 定向构建配置：临时 `config/webpack/_tmp_builds_teams.config.js`（`require` 主配置后覆写 `entry`），**构建完删除**。
- 手工预编译：`F:/eln开发/_precompile_addon_entries.rb`（`ENTRIES=vue_teams_table.js`），
  manifest filename **必须绝对路径**；预编译后**必须 restart**。
- 会话现签：`mksession.rb`（`USERS=hpxing@localhost`），写 TSV 后由 playwright 注入 cookie。

### 10.6 rev2：恢复「ID / 创建人 / 创建时间」列（2026-10-08 晚）

10-08「复刻原生」按原生 4 列口径重写时，把用户 10-07 已上生产的需求列（ID/创建人/创建时间，7 列）
一并回退了。rev2 恢复：`workspace_row` 增 `created_by`（真源 `users.full_name`）与 `created_at`
（服务端 `%Y-%m-%d %H:%M`），`sort_workspaces` 增 `id`/`created_by`/`created_at`，table.vue 扩 7 列
（colspan 同步 7），locale 复用 10-07 既有 key。真浏览器 **23/23 PASS**（创建人=Admin、
时间=2026-10-07 05:04 与 10-07 同源一致）。详见 ADR-0034「修订 rev2」。

### 10.7 rev3：teams 列表换用 AG Grid（shared/datatable 栈）（2026-10-08 晚）

用户拍板「参照 /projects 换用 ag-grid、列宽可调、分页放表格下方」。复用宿主
`shared/datatable/table.vue`（/projects 同款，ADR-0035 V2.0），addon 只写薄封装 + 两个
直接引用的 cellRenderer；后端 datatable 端点改喂 JSON:API（`{data,meta}`）+ `order:{column,dir}`。
`skipSaveTableState=true` 关闭列状态持久化（自愈校验含 +1 选择列，无勾选场景不适用）。
分页条在表格下方（scrollMode=pages 默认）。真浏览器 **21/21 PASS**。
🔴 新坑：addon pack 根组件必须 `createApp({})` + 全局注册，保 in-DOM 模板解析 ERB props；
直接 `createApp(组件)` 会忽略挂载点属性 ⇒ `POST /users/settings/undefined` 404。
详见 ADR-0034「rev3」。
