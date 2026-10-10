//= require i18n.js
//= require i18n/translations
//= require i18n/locale_sync

// ⚠ 不要再 require `scinote/i18n/application`：那是 i18n addon 的资产，
//   而 addon 已于 2026-10-07 从 Gemfile 停用（见 Gemfile 停用记录段）。
//   停用后该文件不再被任何 engine 注册进 assets.precompile，Sprockets 解析不到
//   ⇒ `rails assets:precompile` 抛 FileNotFound ⇒ 整轮镜像构建失败。
//   它原本负责的两件事已拆开：locale 同步 → `i18n/locale_sync`（宿主持有）；
//   语言切换器 UI → 随 addon 一起停用，要恢复请恢复 addon（ADR-0043）。
