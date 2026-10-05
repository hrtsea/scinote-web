# CONTEXT.md — SciNote AI 助手（ai_eln 引擎落地）

> 设计树与决策记录。本文件是 ai_eln 助手功能的**唯一术语与决策来源**。
> 由 ask-matt 路由 → `/grill-with-docs`（= grilling + 书面痕迹）生成（2026-09-24）。

## 1. 目标
在 SciNote 内嵌入一个"实验助手"：用户在实验详情页用自然语言让 AI 摘要/问答/解析，
AI 经统一鉴权操作 SciNote 数据，数据合规可控。ai_eln 原规划的 5 大能力
（summarize / root_cause / parse_recipe / semantic_search / audit_logs）+ 会话/交互 UI 全部实现。

## 2. 代码事实（探查确认，非假设）
- 引擎：`addons/ai_eln` Rails Engine，挂 `/ai_eln`，全局开关 `Scinote::AiEln.enabled?`（默认 **off**）。
- **已实装**：`LlmAdapter`（`app/services/scinote/ai_eln/llm_adapter.rb`，Ollama + OpenAI 兼容后端切换）、
  `AiSummarizeJob`（调 LlmAdapter）、路由 `experiments/:id/summarize`、`root_cause`、
  `protocols/:id/parse_recipe`、`semantic_search`、`audit_logs`、模型 `AiSession`/`AiInteraction`/
  `AiEmbedding`/`AiAuditLog` + 迁移（表已定义；其中 `AiSession`/`AiInteraction`/`AiAuditLog`
  已按 D-persist=B 标记 deprecated，会话/审计改走 actionagent 面板；`AiEmbedding` 仍用于 semantic_search）。
- **ActiveAgent 落地（2026-09-24 后续，迁入引擎内 `addons/ai_eln/app/agents/`）**：
  - `ApplicationAgent < ActiveAgent::Base`（`generate_with :ruby_llm, model:"deepseek-chat"`）—— 引擎内基类。
  - `SciNoteAssistantAgent < ApplicationAgent`，含 `summarize_experiment` / `parse_recipe` / `parse_attachment` / `semantic_search` actions（`root_cause` 仍 TODO；`semantic_search` 依赖 pgvector + neighbor + 已 populate 的 `ai_eln_ai_embeddings`）。
  - `AiActionsController#summarize` 已由 stub 改为调 `Scinote::AiEln::SciNoteAssistantAgent` 返回 `{summary:}` JSON。
  - 全局配置 `config/active_agent.yml`（RubyLLM→DeepSeek + telemetry）；Gemfile 加 `activeagent`/`actionagent`/`ruby_llm`。
  - 前端抽屉/按钮局部已**迁入引擎** `addons/ai_eln/app/views/scinote/ai_eln/experiments/`（`_ai_assistant_drawer.html.erb` 参数化 `actions`/`id`/`input_label` + `_ai_assistant_button.html.erb`），遵循 addons 契约；宿主 `experiments/canvas.html.erb` 经 `scinote/ai_eln/experiments/...` 渲染，不再在宿主 `app/views/experiments/` 留 AI 代码。抽屉局部已参数化 `id`（默认 `aiAssistantDrawer`，全局用 `aiAssistantGlobalDrawer`，避免 DOM id 冲突）+ 可选 `input_label`（语义检索收检索词）。新增 `_ai_assistant_fab.html.erb` 浮动按钮 + 全局抽屉支撑**模式 B 布局全局注入**：宿主 `application.html.erb` 模态区在 `enabled?` 守卫下渲染，`<body>` 透传 `data-ai-entity-type/data-ai-entity-id`，全局抽屉按实体动态追加"摘要/解析本页"按钮并复用现有 per-entity 端点。
- **能力实装状态（2026-09-28 模式 B 实现后）**：`AiActionsController#summarize`/`parse_recipe`/`parse_attachment`/`semantic_search`
  已不再是 stub——调 `Scinote::AiEln::SciNoteAssistantAgent` 对应 action 返回 `{summary:}` / `{result:}` JSON（`semantic_search` 经 `params[:query]` 收检索词）。
  `root_cause` 仍为 `head :not_implemented` + TODO（"其余 4 能力"已完成 3 项）。`AiSessionsController`/`AiInteractionsController`/`AiAuditLogsController` 全空（D-persist=B 已弃用，会话/审计改走 actionagent 面板）。
  **semantic_search 上线前置**：需 pgvector 扩展 + `neighbor` gem + 已 populate 的 `ai_eln_ai_embeddings` 表（ADR-0003）；缺任一项时端点 rescue 后返回友好错误而非崩溃。
  → **ai_eln 仍是脚手架，但 4/5 能力已打通 端点→Agent→DeepSeek（按 D0=B 由 ActiveAgent 实现）；生产可用前仍需 boot 验证 + embedding 管线。**
- 鉴权：**Canaid**（如 `user.can_read_experiment?(exp)`），**非 Pundit**。
- 前端：**Vue 2 + Bootstrap**，**无 Hotwire/Turbo/importmap**。`app/javascript/controllers/` 不存在。
- 实验真实 HTML 页：`experiments#canvas`（`/experiments/:id/canvas`，`routes.rb:493`）——
  `experiments#show` 返回 JSON 序列化器，**不是** HTML 页。
- 实验读取：经 `lists/*_service` + `Lists::*Serializer`，**无 `Experiments::ShowService`**。
- **ActiveAgent 兼容性（2026-09-24 核实）**：gemspec 硬约束 `actionpack >= 7.2, < 9.0`，
  CI 矩阵测 Rails 7.0/7.2 + Ruby 3.2/3.4 → **可直接运行于 SciNote 的 Rails 7.2.3 / Ruby 3.4.8**。
  但 ActiveAgent 的生成器/示例假设 **Rails 8 + Hotwire + Pundit**，须适配 SciNote 现状。

## 3. 决策（已锁定）
- **D0 架构路线 = B（引入 ActiveAgent 框架，实现 ai_eln 全部功能）**【2026-09-24 用户推翻原 A】。
  ai_eln 仅为脚手架，故用 ActiveAgent 提供 agent 运行时 + `action` 能力单元 + 可观测面板，
  来实现 summarize/root_cause/parse_recipe/semantic_search/audit_logs 及会话/交互 UI。
  本决策**取代** `ADR-0001`；理由、风险与适配见 `ADR-0002-introduce-activeagent.md`。
- **D2 模型策略 = C（直接云端）**：偏离"本地优先"合规默认，风险见 ADR-0002 §风险。待 D2a 定 provider 与 dev-only 范围。
- **D3 面板落点 = A（canvas 页 + Bootstrap OffCanvas 抽屉）**：锚定当前 `experiment_id`。
- **D4 页面生效范围与注入方式（2026-09-28 调研；模式 B 详细规划 2026-09-28）**：双轨叠加——(A) **实体页内联**：在 `experiments/canvas`、`protocols/show`、`assets/view` 等 `.html.erb` 渲染**参数化后**的 `_ai_assistant_drawer` 局部，用 `actions[].url` 锚定各自实体（`@experiment`/`@protocol`/`@asset` 已核对存在）；(B) **布局全局注入**：在 `application.html.erb` 模态区（`user_signed_in?` 块内、line 148 之后）`render` 全局 AI 抽屉 + 浮动按钮（FAB，仿 `comments_sidebar`/`file_preview`），覆盖全站。**模式 B 关键设计（已规划、未实装）**：① 抽屉局部须参数化 `id`（默认 `aiAssistantDrawer`，全局用 `aiAssistantGlobalDrawer`）——否则与 canvas 抽屉产生 DOM id 冲突、两个抽屉都坏；② 全局抽屉上下文靠 `<body data-ai-entity-type / data-ai-entity-id>`（布局读 `@experiment/@protocol/@asset` 计算）透传，JS 自动追加"解释/摘要本页"按钮并复用现有 per-entity 端点（无需新控制器 action）；③ 首期主功能 `semantic_search`（当前 stub，须先实现）需抽屉局部支持可选查询文本输入；④ `Scinote::AiEln.enabled?` 守卫开关。**不碰 Vue 组件**（顶部导航 / navigator 是 Vue，ERB 注入只在布局模态层）。详见方案 §7 / §7.7。

## 4. 开放前沿（实现前最后一轮）
- **D1-scope 首期范围**：全量 5 能力一次实现 vs 先 PoC（summarize 打通 + 最小 UI）再复制。推荐 PoC 优先降险。
- **D1 能力→action 映射**：用 ActiveAgent 的 `action` 单元实现各能力；`summarize_experiment` 作 tracer bullet
  （Agent action → 复用 `lists/*_service`/`AiSummarizeJob` → ruby_llm 云端）。
- **D2a 云端 provider / 模型 / API key 存储 / dev-only 还是 production**：
  DeepSeek（OpenAI 兼容、中文友好）vs OpenAI vs 其他；key 存 Rails credentials 还是 env；
  确认 Q2=C 是仅开发期/非敏感数据验证，还是生产也走云端（后者需合规签字）。
- **D-persist 持久化/审计 = B（全盘替换，2026-09-24 用户确认"全盘替换"）**：弃用 ai_eln 的 `AiSession`/`AiInteraction`/`AiAuditLog` 空模型（仅建表、无接线），改由 ActiveAgent 的 **actionagent 面板（solid_agent）** 统一承载会话追踪 / token·成本 / 对话 / 审计导出（AI-403）；避免双写。推理统一走 `ruby_llm`，`LlmAdapter` 退居可选 / 移除。三模型已加 `DEPRECATED` 横幅（见 ADR-0002「全盘替换范围与理由」）。
- **D3a 抽屉注入方式**：Rails 局部 + Bootstrap OffCanvas 挂 `canvas.html.erb`，经 fetch/XHR 调 ActiveAgent 端点
  （非 Hotwire）；不改动 Vue 构建链。

## 5. Avoid（禁止 / 慎行）
- 不假设 ActiveAgent 的 **Hotwire/Turbo/Pundit 脚手架**可直接套用（SciNote 是 Vue 2 + Bootstrap + Canaid）；
  其生成器输出须改写为 Vue/Bootstrap 局部 + fetch 调 agent 端点，鉴权改走 Canaid（见 ADR-0002 §适配）。
- 不假设 `Experiments::ShowService` 存在（读取走 `lists/*_service`）。
- 写操作必须经 Canaid 权限闸 + 用户确认，防 Agent 误写。
