# 0006 — 配方成为一等实体（Formulation）

## Status

Proposed

## Context

配方研发（AI-ELN 延展方向）需要结构化"配方 + 目标性质"记录，以支撑监督学习 / 贝叶斯优化。现有 `CONTEXT.md` 定义 **配方（recipe）= `Form`/`Table` 结构化字段 + `Repository` 行，且"无 recipes 表"**；同时 `ai_eln` 的 `configuration.rb` 已预留 `recipe_class = "Recipe"` 宿主契约，设计上计划引入配方模型。用户诉求"构建结构化记录"要求一等实体，而非继续隐式承载。

候选：
- A. 一等实体：新增 `Formulation` / `FormulationComponent` / `FormulationProperty`。
- B. 派生：配方 = 现有 `MyModule` + `RepositoryRow` 关联（`MyModuleRepositoryRow.stock_consumption` 已是用量），仅新增 `FormulationProperty` 性质表。

约束（已查证源码）：
- 组成+用量已在 `MyModuleRepositoryRow.stock_consumption`，但单位来自 `repository_stock_unit_item`、语义是"消耗"非"投料比例"，且配方无法脱离具体任务复用。
- 结果数值藏在 `Result`→`Table.contents`（JSON 网格），需解析抽取才能当 label。
- `ai_eln` 引擎模型约定：继承 `ActiveRecord::Base` + `self.table_name`，宿主模型经 `configuration.x_class` lambda 引用，表前缀 `ai_eln_`。

## Decision

采用 **方案 A**：

1. `Formulation`（表 `ai_eln_formulations`）：配方组成定义，含 team / created_by / name / description。
2. `FormulationComponent`（表 `ai_eln_formulation_components`）：一个成分（`repository_row_id` 复用宿主物料主数据）+ 投料量(amount/unit)，唯一约束(配方, 物料)。
3. `FormulationProperty`（表 `ai_eln_formulation_properties`）：配方性质，`measured_value`+`measured_unit`（实测）+ 可选 `target_value`+`comparator`（目标指标）；`my_module_id` 指向宿主实验任务实例，设计目标为 NULL（支持同配方多批次，S3）。

性质同时含实测值与目标值，直接支撑监督学习 label 与优化约束。

## Consequences

- 推翻 `CONTEXT.md` 既有"配方=Form/Table、无 recipes 表"定义，已更新 glossary（`配方(formulation)` 等词条）。
- 零侵入：仅引擎内新增 3 张表 + 模型，不改动宿主 `Form`/`Table`/`Repository` 代码。
- `configuration.recipe_class`（宿主契约占位）与引擎内 `Formulation` 并存；`recipe_class` 指宿主 `Recipe`，暂未使用，后续如需统一再决策（不在本 ADR 范围）。
- 单位归一化（S2：g/mL/mol 差异）不在 schema 强制，交由读取/训练抽取层处理。
- 配方与实验的归属仅通过 `FormulationProperty.my_module_id` 弱关联；若需"配方挂载到实验"的组织结构，后续再加关联。
