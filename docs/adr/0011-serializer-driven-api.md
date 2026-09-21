# 0011 — 序列化器驱动 API 与导出输出

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-004（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（图谱）

## Context

API 与导出输出形态现状：57 个序列化器文件；`Lists::MyModuleSerializer#attributes`（163）是热点函数；重度使用 `active_model_serializers`。

## Decision

- 模块 / 仓库的 JSON 形态由**序列化器**生成。
- 序列化逻辑应保持在**控制器之外**。

## Consequences

- 修改输出形态时改序列化器，而非在控制器内拼接 JSON。
- 新增实体的「模型 + 序列化器 + 控制器 + 权限 + factory + spec」应按约定强耦合补齐（见防护建议）。

## 关联

- 0008（Repository 渲染稳定性关键区）
