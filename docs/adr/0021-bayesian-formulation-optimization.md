# 0021 — 贝叶斯配方优化（AI-501）数据来源与计算后端

> 来源：原 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-015（已于 2026-09-21 归并到 `docs/adr/`）。

## Status

Proposed（规划）

## Context

spec 原 §8.2「贝叶斯优化闭环」此前列为非范围；现纳入范围。需确定训练数据从 SciNote 何处读取、候选如何产出（且生成 draft 不得扣库存）、计算后端形态。关联：`docs/ai-eln/实现现状与开发计划.md` §12、`docs/ai-eln/CONTEXT.md` §五 / §六。

## Decision

1. **指标 + 工艺参数**统一从 `my_module` 的 `ResultTable` 命名列读取（按列名匹配），**不引入新 measurements 表**（spec 假想表不存在）。
2. **抽样单元 = `my_module`（`status=completed`）**：一条样本 = 该任务经 `MyModuleRepositoryRow` 挂接的 `RepositoryRow` 的 `stock_consumption` 组分向量 + 其 `ResultTable` 指标 / 工艺向量。
3. **配方 / 组分质量份映射 = 方向 X（鹰谷-lite，无配方实体表）**：基准配方 = SciNote 实验模板（`CopyExperimentAsTemplateService`），实验配方 = 克隆实验内 `MyModuleRepositoryRow#stock_consumption`（组分质量份），工艺 / 性能 = `ResultTable` 命名列；变量 / 固定区分经轻量「优化配置」（per 基准模板记变量组分 + 上下界）。抽取经可配置 `RecipeAdapter` 抽象，default 即方向 X 适配器；真实结构变更（如改方向 Y 建配方表）仅新增 adapter 子类，核心不写死。（**状态：2026-09-03 已锁定方向 X**）。
4. **计算后端 = 纯 ruby（无 python）**：默认 `Numo::NArray` 做矩阵运算 + 自实现高斯过程（RBF / Matern 核 + Cholesky 求解），采集函数 EI / UCB，单目标优先。
5. **候选产出（方向 X）= 表格预览 + 人工粘贴**：候选以表格呈现（组分质量份 + 工艺参数，标注预测均值 ± 方差），**不自动建实验、不进入 `MyModuleRepositoryRow` / stock 路径**，用户确认后人工粘贴到从基准模板克隆的实验（HITL）→ 满足「生成候选不扣库存」约束。

## Consequences / 风险

- 纯 ruby GP 对多目标与硬约束支持弱（v1 仅单目标稳健，多目标用加权标量化近似）；样本需 ≥~8 条才有意义。
- `Numo` 为新增纯 ruby gem（零 python）；配方映射已定方向 X（无配方实体表）。
- AI-501 不调 LLM，纯数值，审计照落 `ai_audit_logs`。

## 关联

- 0001（AI-ELN，落地载体）
- 0004（LLM 适配层——本 ADR 不依赖 LLM）
- 0020（addon 配置自声明）
- `docs/ai-eln/CONTEXT.md`、`docs/ai-eln/实现现状与开发计划.md`（P1–P17 Issue 拆分）
