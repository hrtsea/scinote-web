# 04 — AI 侧边抽屉 UI 与权限条件渲染

**What to build:** 在实验页面、配方（Form/Table）页面、项目页面注入 AI 助手侧边抽屉（drawer partial），通过 SciNote 官方视图 hook 注入，不侵占原生布局。所有 AI 操作按钮/面板以 Canaid `ai:use` permission 控制可见性，viewer（只读）角色隐藏全部 AI 操作；drawer 内含"停止生成"取消按钮（置 `ai_interactions` 为 cancelled）。

**Blocked by:** 03 — LLM 适配层与异步流式管道

**Status:** ready-for-agent

- [ ] 实验/配方(Form·Table)/项目页面注入 drawer partial（经官方视图 hook，不覆盖原生视图）
- [ ] AI 操作按钮/面板按 `ai:use` permission 条件渲染
- [ ] viewer 角色下全部 AI 操作按钮不可见
- [ ] drawer 含"停止生成"按钮，触发 `ai_interactions` 置 cancelled（GLP 留痕）
- [ ] 人工确认预览→复制/存附件的交互模式可用（AI 结果绝不自动写入原始记录）
- [ ] 符合 ADR-0001（权限）、ADR-0004（cancelled 状态）
