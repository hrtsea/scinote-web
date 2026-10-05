# 0013 — AI 协议生成以 addon 形式实现（ai_protocols）

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-006（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted

## Context

官网 AI & Automations 页的 Create with AI / Import with AI；代码库现状 `Protocol.ai_parser_enabled?`（`app/models/protocol.rb:293`）已预留「`ApplicationSettings` 键 `ai_protocol_parser_enabled` + ENV `AI_PROTOCOLS_PARSER`」双重门控，但全仓无任何消费方、无 LLM 客户端。

## Decision

- 以独立 Rails Engine `addons/ai_protocols/`（`Scinote::AiProtocols::Engine`，`isolate_namespace`）承载全部 AI 协议生成逻辑；**绝不修改核心 `app/`**。
- LLM 接入：OpenAI 兼容 Chat Completions + 结构化输出（JSON schema）；`AI_PROTOCOLS_PARSER` 即 base URL（兼容 Azure OpenAI）；新增 `AI_PROTOCOLS_API_KEY`、`AI_PROTOCOLS_MODEL`（默认 `gpt-4o-mini`）。`LlmClient` 用策略模式，未来可加 Claude / Ollama 而不改调用方。
- 生成内容对齐 `ImportProtocolService`（`app/services/protocol_importers/import_protocol_service.rb`）的 `steps_params` schema（name/position/description/tables_attributes），直接喂入落库，不碰核心创建逻辑。
- 协议落点为**协议模板草稿**（draft template），用户审核 / 编辑后再导入项目。
- 权限文件置于 addon `app/permissions/**/*.rb`，由 `config/initializers/canaid.rb` 自动发现。

## Consequences / 风险

- 若上游未来自行实现并消费 `ai_parser_enabled?`，本 addon 经 `app/decorators` / `app/overrides` 的覆盖可能产生冲突——覆盖点须记录在 `docs/开发计划/ai-eln/实现现状与开发计划.md` 并随上游演进复核。

## 关联

- `docs/development/addon-dev-workflow.md`（addon 方法学）
- `docs/开发计划/ai-eln/实现现状与开发计划.md`（PRD / Issues）
- 0020（addon 配置自声明：ai_protocols 已声明 `parser_url`/`api_key`/`model` schema，首轮仅暴露未消费）
- 0001（AI-ELN 为姊妹 addon，自有 `LlmAdapter`，不复用本 addon 的 `LlmClient`）
