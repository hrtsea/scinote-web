# 01 — AI-ELN Engine 骨架与零侵入挂载

**What to build:** 一个可挂载到 SciNote 的独立 Rails Engine addon（`addons/ai_eln`，模块命名空间 `Scinote::AiEln`，以 `Scinote` 前缀被官方 `list_all_addons` 发现机制识别），通过官方 addon 扩展点注入全部 AI 能力。包含 initializer 路由注入、Canaid `ai:use` permission 注册、以及可配置开关（`enable` / `llm_backend` / `api_endpoint` / `model_name` / `max_token` / `ocr_backend` / `llm_retry`）。当 `enable=false` 时完全不加载 AI 路由与 UI，系统退化为原生 SciNote，原生数据不受影响。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

> 注：骨架已按官方 addon 脚手架（`lib/generators/addon`，name=`Scinote::AiEln`）落实于 `addons/ai_eln/`。

- [x] Engine 在 `addons/ai_eln` 下创建（`Scinote::AiEln`），通过根 `Gemfile`（`gem 'scinote_ai_eln', path: 'addons/ai_eln'`）+ `mount Scinote::AiEln::Engine => "/ai_eln"` 挂载到 SciNote
- [x] Canaid 扩展点注册 `ai:use` permission，挂到 owner/normal_user/technician，viewer 不授予（接入片段见 `addons/ai_eln/integration/host_initializers/scinote_ai_eln.rb`）
- [x] config 支持 `enable` 全局开关；`config/routes.rb` 内 `return unless Scinote::AiEln.enabled?` 在 false 时不加载 AI 路由
- [x] config 支持 `llm_backend` / `api_endpoint` / `model_name` / `max_token` / `ocr_backend` / `llm_retry`
- [ ] `enable=false` 时原生 SciNote 页面、数据、权限无任何差异（验证）
- [ ] 不修改 SciNote 核心模型、控制器、迁移（零侵入约束验证）
