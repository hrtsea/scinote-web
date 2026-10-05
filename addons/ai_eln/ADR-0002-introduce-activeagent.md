# ADR-0002: 引入 ActiveAgent 实现 ai_eln 全部功能

- **状态**：已采纳（2026-09-24，用户推翻 ADR-0001 的路线 A）
- **取代**：`ADR-0001-architecture-route.md`（原决策"完成 ai_eln 引擎、不引入 ActiveAgent"被本决策推翻）
- **背景**：探查发现 `addons/ai_eln` 虽已就位 `LlmAdapter`/`AiSummarizeJob`/路由/模型，但 4 个控制器全是  
  `head :not_implemented` stub、前端 UI 全空——**ai_eln 整体仅是脚手架，功能未实现**。原 ADR-0001 主张"填空  
  stub 完成 ai_eln"，用户最终裁决改为**引入 ActiveAgent 框架来实现 ai_eln 的全部功能**。

## 决策

**引入 ActiveAgent gem**，以其 agent 运行时 + `action` 能力单元 + 可观测面板为底座，实现 ai_eln 规划的  
全部能力（summarize / root_cause / parse_recipe / semantic_search / audit_logs）及会话/交互 UI。

## 理由

1. **加速 stub 补全**：ActiveAgent 自带"Agents are Controllers"运行时、action 声明式能力单元、provider 抽象  
   （ruby_llm 15+ 家）、actionagent 可观测面板——这些正是 ai_eln stub 缺口要补的东西，引入可大幅减少自研。
2. **ActiveAgent 可运行于 SciNote 版本**：gemspec `actionpack >= 7.2, < 9.0`，CI 测 Rails 7.0/7.2 →  
   兼容 SciNote 的 Rails 7.2.3 / Ruby 3.4.8（已核实）。
3. **用户明确裁决**：在知悉"与 ai_eln 重复 / Hotwire-Pundit 假设错配"等代价后仍选择引入，以换取开发速度与  
   完整 agent 能力。

## 风险 / 适配（必须处理）

- **UI 错配**：ActiveAgent 脚手架假设 Hotwire/Turbo/Pundit。SciNote 是 Vue 2 + Bootstrap + **Canaid**。  
  → 不套用其生成器 UI；自建 Vue/Bootstrap OffCanvas 抽屉，经 fetch 调 agent 端点；鉴权改走 Canaid。
- **依赖膨胀**：ActiveAgent 1.2.0 引入 `ruby_llm >= 1.0` 与 `aws-sdk-bedrockruntime`（运行依赖）。  
  → 与 ai_eln 现有 `LlmAdapter` 可能重复；建议推理统一走 ruby_llm，LlmAdapter 退居可选/移除。
- **持久化/审计全盘替换（D-persist=B，用户 2026-09-24 确认"全盘替换"）**：ai_eln 的 `AiSession`/
  `AiInteraction`/`AiAuditLog` 仅是**未接线的空模型**（仅迁移建表，无读写逻辑、控制器全 stub）。  
  → 由 ActiveAgent 的 **actionagent 面板（solid_agent）** 统一承载会话追踪、token/成本、对话与审计导出
  （AI-403）。**弃用并标记这三张表为 deprecated**，避免双写、双维护、双故障面。详见下文"全盘替换范围"。
- **多引擎集成**：ActiveAgent 与 ai_eln 均为 Rails Engine。→ Agent 定义置于 `addons/ai_eln/app/agents`  
  （feature 命名空间内），由 ai_eln 的路由/开关/`enable` 统一挂载。

## 全盘替换范围与理由（D-persist=B）

**范围澄清**：本 ADR 的"引入 ActiveAgent 实现 ai_eln"= 以 ActiveAgent 的 agent 运行时 + action 能力单元
+ actionagent 可观测面板，**整体替换** ai_eln 的半成品实现——包括其未接线的 `AiSession`/`AiInteraction`/
`AiAuditLog` 三张表。ai_eln 引擎**仅保留为挂载壳**（routes / `enable` 开关 / `Scinote::AiEln` 命名空间），
不再自维护一套会话/审计存储。

**为何选全盘替换而非保留 ai_eln 模型**：
1. ai_eln 三张表是"建表即止"的空壳——无 controller 读写、无 service 接线，等价于不存在。保留它们等于
   自行再写一套 agent 会话/审计存储，与 actionagent 面板（已提供 trace/token/cost/对话落库）**功能完全重合**，
   双写徒增维护与故障面。
2. 单一可观测来源：actionagent 面板把每次 agent run 的 prompt/response/token/成本/对话集中存储并可视化，
   合规审计导出（AI-403）可直接复用，不必自维护 `ai_eln_ai_audit_logs`。
3. 单一推理客户端：ruby_llm 取代 `LlmAdapter`，token 计量统一由 actionagent telemetry 收集，避免两套计量。
4. 代价可控：已知 Hotwire/Canaid 适配、依赖膨胀（aws-sdk-bedrockruntime）等代价，用户已裁决接受以换取
   开发速度与完整 agent 能力。

**代码体现（本会话落地）**：
- `addons/ai_eln/app/models/scinote/ai_eln/ai_session.rb` / `ai_interaction.rb` / `ai_audit_log.rb`：
  加 `DEPRECATED` 横幅，标记被 actionagent 取代；表保留（已建），新写入逻辑不再产生。
- `AiActionsController#summarize`：调 `generate_now` 后**不**写 `AiInteraction`/`AiAuditLog`，
  审计/追踪委托 actionagent telemetry。
- `ai_audit_logs#index` 路由/控制器：标记 deprecated，审计导出改走 actionagent 面板。
- 后续迁移（实例 boot 后）：统一 `drop_table` 三张表并移除模型/路由（待定，避免离线断链）。

## 合规风险（D2=C 直接云端）

SciNote 存材料配方 / 实验专有数据。D2=C 选直接云端模型 → 专有数据出网。

- 开发期 / 非敏感（合成）数据验证：可接受，用于打通链路。
- 生产环境走云端：需合规签字，明确数据出网范围与第三方数据处理条款。
- 长期推荐：自托管机具本地推理能力后，经 ruby_llm 切回 Ollama（ActiveAgent 原生支持），回归"数据不出网"。
