# 0002 — AI 调用审计日志：独立 Engine 表

## Status

Accepted (基于 0001 的零侵入约束推导)

## Context

需求规格 §4 要求每次 AI 调用持久化：操作用户、时间、输入 prompt、AI 返回、模型名称、token 消耗，并支持管理员导出。GLP 合规要求 AI 内容与原生人工记录明确区分、可审计。

候选方案（已查证 `app/models/activity.rb`）：

- **A. Engine 内独立 `ai_audit_logs` 表**：零侵入，GLP 隔离最干净，合规导出走 Engine 自有表。
- **B. 复用原生 `Activity`**：直接 `Activity.create!` 挂现有 `type_of`，不改 schema，但 AI 审计混入原生流、无专属 type，过滤困难。
- **C. 扩展 `Extends::ACTIVITY_TYPES`**：加 `ai_call` 专属 type，统一流最完整，但需改 SciNote 的 `Extends` 模块，违反 0001 的零侵入约束。

约束：`Activity` 的 `subject_type` 受 `Extends::ACTIVITY_SUBJECT_TYPES` 白名单、`type_of` 受 `Extends::ACTIVITY_TYPES` 枚举约束，且无官方封装创建入口。零侵入与"复用原生 Activity 统一流"不可兼得。

## Decision

采用 **方案 A**：AI 调用审计存放于 Engine 内部独立表 `ai_audit_logs`，不写入 SciNote 原生 `Activity`。

- `ai_audit_logs` 字段：`user_id`、`created_at`、`prompt`、`response`、`model_name`、`token_usage`、`status`、`ai_sessionable` 多态关联（指向被操作的 Experiment/StepText/ResultText/FormResponse/Table）。
- 合规导出由 Engine 提供独立导出接口（管理员角色可调用）。
- 不扩展 SciNote `Extends` 模块，保持零侵入。

## Consequences

- GLP 下 AI 调用与原始人工记录物理隔离，审计边界清晰。
- 放弃原生 Activity 统一流，但换来零侵入与隔离性，符合 0001 总原则。
- 注意：原生 `Activity` 仍记录用户"触发 AI 操作"这一动作（若用 Canaid permission 包装触发入口，可顺带在原生流留痕），但 AI 的输入输出详情只在 `ai_audit_logs`。
