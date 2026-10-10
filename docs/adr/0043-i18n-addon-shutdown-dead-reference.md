# ADR-0043:停用 i18n addon 后 i18n_bundle 的死引用拆分

## Status

Accepted（2026-10-10）

## Context

2026-10-07 停用 `i18n` addon（Gemfile:163 注释掉 `gem 'scinote_i18n'`），当时的核查范围是
「宿主 `app/ lib/ config/` 不引用 i18n addon 的 `ControllerLocale` / `UserLocale` / `Scinote::I18n`
命名空间」⇒ 结论为「停用安全，仅失去语言切换入口」。

**这次核查漏了一路：Sprockets 资产引用。**

`app/assets/javascripts/i18n_bundle.js:3` 无条件 `//= require scinote/i18n/application`，
而该文件由 addon 提供，addon 的 engine 靠

```ruby
# addons/i18n/lib/scinote/i18n/engine.rb:11
app.config.assets.precompile += %w(scinote/i18n/application.js)
```

把它注册进 Sprockets。addon 停用 ⇒ 这个 initializer 不跑 ⇒ 文件不在 Sprockets 索引里 ⇒
`rails assets:precompile` 抛

```
Sprockets::FileNotFound: couldn't find file 'scinote/i18n/application'
  with type 'application/javascript'
  被 app/assets/javascripts/i18n_bundle.js:3 引用
```

⇒ **整轮镜像构建在最后一步失败**，而前面 10 分钟的 106 个 webpack entry 全部白跑。

被require 的 `addons/i18n/app/assets/javascripts/scinote/i18n/application.js` 干两件事：

1. `I18n.locale = currentLocale()`——把前端 locale 对齐到服务端解析值。
   值从 `<meta name="scinote-locale">` 读（`layouts/application.html.erb:9` 服务端渲染），
   cookie 仅兜底。
2. `buildSwitcher()`——往每个页面注入语言切换器 UI，POST `/users/settings/locale`。

第 ① 项**必须保留**：`eln_ui` / `workbench` 的 Vue 页面把 `window.I18n` 注入
`app.config.globalProperties.i18n`（见 `addons/eln_ui/.../packs/eln_project_list.js` 与
`entries/res_center.js:54`），供宿主 `shared/datatable/table.vue` 及各 cellRenderer
调`this.i18n.t(...)`。locale 错 ⇒ 全站 Vue 页文案错（且「错语言」比「不渲染」更难被肉眼发现）。
第 ② 项是 addon 真正独有价值，**随 addon 一起停用即符合 10-07 的决定**。

## Decision

把两件事拆开：locale 同步下沉到宿主，切换器 UI 随 addon 停用。

- 新增 `app/assets/javascripts/i18n/locale_sync.js`——只做 ①，纯前端、读 meta、无网络请求，
  不依赖 addon 任何 Ruby 侧常量（可用 locale 列表内联为 `['en','zh-CN']`）。
- `i18n_bundle.js`：把 `//= require scinote/i18n/application` 换成
  `//= require i18n/locale_sync`，并在原位留注释说明「不要再 require 回来」及其后果。

**否决方案：**

| 方案 | 否决理由 |
|---|---|
| 恢复 i18n addon（解注释 Gemfile:163） | 与10-07「缩小默认装载面」的出发点相反；且构建期刚因该 addon 的死引用失败过一轮，方向相反容易再踩 |
| 直接删掉那行 require | 最省事，但 `I18n.locale` 永不复位 ⇒ 前后端 locale 不一致 ⇒ eln_ui/workbench 全部 Vue 页文案可能错语言。**属静默降级**，比构建失败更糟 |
| 在 bundle 里内联回整份 application.js | 把停用 addon 的代码复制进宿主，违背「同一事实只许一个真源」；切换器 UI 会与 addon 恢复后重复 |

**顺带修正 ADR-0042 的适用范围**：`SKIP_ACCESS_CONTROL_DB_CHECK` 当时只加给了
`zeitwerk:check`（静态检查，不需要 Rails environment），漏了
`rails tailwindcss:build` 与 `assets:precompile`（**两者都加载完整 environment**，
都会触发 engine 的 `before` 回调 → `verify!`）。已在 Dockerfile 补齐三处，并加注释
「漏加会在 yarn build 全跑完、10 分钟后才炸」。

## Consequences

- **更容易**：`assets:precompile` 恢复可跑；前后端 locale 恒等（meta 是服务端渲染，比 cookie
  可靠，不受 SameSite / 第三方拦截影响）；`i18n_bundle` 不再依赖任何已停用 addon。
- **更难**：语言切换入口没有了（10-07 停用时已接受的后果，此处只是让它在构建期也说得通）。
  要恢复，正确做法是恢复 addon 并删掉 `locale_sync.js`——**两处必须同时改**，
  否则会出现双重同步（`locale_sync` 与 addon 的 `application.js` 都写 `I18n.locale`，
  虽然值相同不会出错，但属重复真源）。
- **新增一条元规则**：停用 addon 时，核查范围必须含**三路**——Ruby 命名空间引用 /
  Sprockets 资产（`app/assets/**`的 `//= require`）/ 路由与资源登记（`config/initializers/assets.rb`、
  `webpack.config.js` entryList）。10-07 只查了第一路。
