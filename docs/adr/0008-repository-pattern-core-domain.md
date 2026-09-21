# 0008 — Repository（自定义表）模式是核心领域模型

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-001（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Accepted（由 codebase-memory 知识图谱推导，稳定性事实）

## Context

codebase-memory 知识图谱（16,158 节点 / 46,071 边）对 SciNote 全量索引后推导出的核心领域模型事实。`RepositoryRowService#render` 是全局 fan-in 最高的函数（819 个调用方），`repository_*` 聚类是内聚性最强的组之一。

## Decision

- `Repository` / `RepositoryRow` / `RepositoryColumn` 及值类型家族（`repository_text_value`、`repository_list_value`、`repository_stock_value` 等）构成数据模型的骨干。
- 将其视为**稳定性关键子系统**：对仓库值渲染 / 序列化的改动影响面最广。

## Consequences

- 重构该子系统前应先补充刻画性测试（见 0005 新增实体约定）。
- 任何触及仓库行渲染的改动都需评估波及面。

## 关联

- 0005（addon 注册约定：新增领域实体须补齐权限文件）
- 六、后续开发的防护建议（ARCHITECTURE_DECISIONS.md）
