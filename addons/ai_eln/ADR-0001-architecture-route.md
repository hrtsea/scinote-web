# ADR-0001: SciNote AI 助手架构路线

> ⚠️ **本 ADR 已被取代**：2026-09-24 用户最终裁决推翻本决策（路线 A），改为**引入 ActiveAgent 框架实现 ai_eln 全部功能**（路线 B）。
> 现行有效决策见 **`ADR-0002-introduce-activeagent.md`**。本文件保留为决策追溯，正文不再更新。

- **状态**：已采纳（2026-09-24，grill Q0=A） → **已被 ADR-0002 推翻（2026-09-24 16:32）**
- **背景**：原方案（早期 `output/SciNote内嵌助手Agent方案.md`）拟"引入 ActiveAgent gem，在 SciNote 内造
  助手 Agent"。探查 `scinote-web` 源码发现 SciNote **已自带 `addons/ai_eln` 引擎**——
  `LlmAdapter`（Ollama / OpenAI 兼容）、`AiSummarizeJob`、summarize/root_cause/parse_recipe/
  semantic_search/audit_logs 路由、AiSession/AiInteraction/AiEmbedding/AiAuditLog 模型 + 迁移
  均已就位，仅控制器为 stub、前端 UI 为空。

## 决策
**完成现有 ai_eln 引擎**（填空控制器 stub + 建最小前端抽屉），**不引入 ActiveAgent**。

## 理由
1. **单一可信源**：ai_eln 已是官方 AI 架构，再引 ActiveAgent 等于并行第二套 AI 框架，
   直接违背 agent-native「能力单一可信源、多入口同源复用」的核心原则。
2. **技术错配**：ActiveAgent 假设 Rails 8 + Hotwire + Pundit；SciNote 实际是 Rails 7.2 +
   Vue 2 + Bootstrap + **Canaid**。强行集成成本高、收益低。
3. **已有 LLM 适配层**：`LlmAdapter` 已支持 Ollama / OpenAI 兼容后端，无需另起炉灶；
   `AiSummarizeJob` 已把"调 LLM 做摘要"的实现写好，只差接线。

## 风险 / 权衡
- 工作量集中在"填空控制器 stub + 前端抽屉"，而非"引框架"——但这是**补全既有架构**，
  比并行新增框架更可持续。
- 关联决策：D2（云端模型，合规风险见下）、D3（canvas 页 Bootstrap OffCanvas 抽屉）。

## 合规风险（D2=C 直接云端）
SciNote 存材料配方 / 实验专有数据。D2=C 选择直接云端模型，意味着这些专有数据会出网到第三方 LLM。
- 若为**开发期 / 非敏感（合成）数据验证**：可接受，用于打通链路。
- 若**生产环境**也走云端：需合规签字，明确数据出网范围与第三方数据处理条款。
- 长期推荐：待自托管机具备本地推理能力后，经 `LlmAdapter` 切回 Ollama（架构已预留），回归"数据不出网"。
