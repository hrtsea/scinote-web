# 03 — LLM 适配层与异步流式管道

**What to build:** AI 调用的统一后端：Delayed Job worker 调用 LLM（Ollama 本地 / OpenAI 兼容 API，按 config 切换），经 Solid Cable 频道向发起用户的 drawer 实时流式推送 token；重试按 `llm_retry` 配置（默认关，指数退避限 3 次）；流正常结束或重试耗尽后一次性写 `ai_audit_logs` 完整记录。以 AI-001（实验方案生成）作为端到端载体验证整条管道。

**Blocked by:** 01 — Engine 骨架与零侵入挂载; 02 — AI 数据模型迁移

**Status:** ready-for-agent

- [ ] LLM 适配层封装 Ollama / OpenAI 兼容两种后端，经 config 切换
- [ ] Delayed Job worker 接收 AI 请求入队，不阻塞 web 进程
- [ ] Solid Cable 频道在首 token 起流式推送，drawer 渐进渲染
- [ ] `ai_interactions` 状态机流转：queued→streaming→completed/failed/cancelled
- [ ] 重试按 `llm_retry` 配置（默认关）；开启时指数退避限 3 次
- [ ] 流结束（completed）或失败（重试耗尽）时写 `ai_audit_logs` 完整 prompt+response
- [ ] 用 AI-001 验证：从触发到 drawer 显示结果、审计落库，端到端打通
- [ ] 符合 ADR-0004
