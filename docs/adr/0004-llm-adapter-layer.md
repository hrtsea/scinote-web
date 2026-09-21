# 0004 — LLM 适配层：异步流式 + 可配置重试

## Status

Accepted (收敛自 V1.1 §10 未决项：LLM 适配层)

## Context

AI-ELN 的所有 AI 能力（AI-001~AI-403）最终都经一个 LLM 适配层调用大模型。需确定其执行模式、重试策略、流式输出，以及由此决定的 `ai_interactions` 状态机与审计写入时机。

约束（已 grill + 查证）：
- 本项目后台队列为 Delayed Job（0001），实时通道为 Solid Cable（AGENTS.md：WebSockets 用 Solid Cable）。
- 后端可配置（Ollama 本地 / OpenAI 兼容 API），本地 14B 模型可能分钟级延迟。
- GLP 合规要求 AI 调用输入输出完整留存、可追溯（0002）。

## Decision

1. **执行模式：异步 + Solid Cable 推送**
   AI 请求入 Delayed Job 队列，worker 调用 LLM；首 token 起经 Solid Cable 频道向发起用户的 drawer 实时推送。复用项目现有 Solid Cable，不引入新通道。Web 进程不阻塞。

2. **流式输出：开启（token 级渐进）**
   适配层以 SSE/stream 方式消费 LLM 响应，逐 token 经 Cable 推送；drawer 渐进渲染。与异步+Cable 天然契合。

3. **重试策略：可配置**
   全局 config 开关（`llm_retry: true/false`）决定失败是否重试。开启时指数退避、限 3 次；关闭时（GLP 严格模式）失败仅记 `failed`，用户手动重发。默认建议关闭（合规优先）。

4. **`ai_interactions` 状态机**
   `queued` → `streaming`（首 token 到达）→ `completed` / `failed` / `cancelled`
   - `cancelled`：用户中途取消流式生成时置位；已推送 token 标记为"未完成-用户取消"，GLP 下留痕可追溯。
   - 允许中途取消（用户授权内），但取消动作本身记入审计。

5. **审计写入时机：流结束后一次性写完整 response**
   `ai_audit_logs` 仅在流正常结束（completed）或最终失败（failed，重试耗尽）时写入**完整** prompt + response。中断/取消（cancelled）不写完整 response，仅在审计记"取消"事件与已生成片段标记。契合 0002"完整留存、可复核"。

## Consequences

- 零侵入：复用 Delayed Job + Solid Cable，无新基础设施。
- UX：流式渐进 + 实时推送，优于轮询。
- 合规：可配置重试（默认关）+ 完整审计 + 取消留痕，满足 GLP 可追溯。
- `ai_interactions` 需增加 `cancelled` 状态与取消时间戳字段；适配层需实现 stream 消费与 Cable 广播。
- 取消能力要求 drawer 前端提供"停止生成"按钮（受 `ai:use` permission 控制）。
