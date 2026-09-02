# AI-ELN 领域术语表（CONTEXT.md）

> 本文件是 AI-ELN 插件的**纯术语表（glossary）**，不含任何实现细节。
> 作为本插件开发会话的「通用语言」来源；实现决策见 `实现现状与开发计划.md` 与 `docs/ARCHITECTURE_DECISIONS.md` 的 ADR-014。
> 术语若与 SciNote 核心术语冲突，以本表为准并在 ADR 中记录。

## 一、插件与边界

- **AI-ELN 引擎（ai_eln addon）**：本插件的 Rails Engine 形态，命名空间 `Scinote::AiEln`。完全独立于 SciNote 核心，可整体启停。
- **原生 SciNote（host）**：被挂载的 SciNote 主应用。实验/配方/样品/权限/审计追踪/电子签名**不可被本插件修改**。
- **零侵入（zero-intrusion）**：不修改 host 的 `app/`、`config/routes.rb`、`config/application.rb`、宿主 `db/migrate`；本插件通过 Engine 自注册路由、deface 视图覆盖、decorator、initializer 注入。
- **启停（enable/disable）**：通过全局开关关闭后，系统**完全退化为原生 SciNote**，原有数据不受影响。

## 二、AI 能力术语

- **LLM 适配层（LlmAdapter）**：统一封装对大模型的调用，屏蔽 Ollama 本地 / OpenAI 兼容 API 的差异。仅暴露「发 prompt、收结构化结果」的接口。
- **本地私有化大模型（Ollama）**：部署在用户内网的 LLM（如 `qwen2.5`），通过 `http://127.0.0.1:11434/v1` 暴露 OpenAI 兼容接口，防止配方数据外泄。
- **OpenAI 兼容 API**：任意遵循 `/v1/chat/completions` 协议的远端服务。
- **结构化输出（schema-constrained）**：要求 LLM 按 OpenAI `json_schema` 严格返回 JSON，避免自由文本难解析。
- **人工确认（human-in-the-loop / HITL）**：AI 生成的任何内容**必须**经用户预览并显式确认，才允许落入业务；**禁止自动写入原始实验记录**。
- **AI 辅助生成标记**：所有 AI 产出在 UI 与存储上标注「AI 辅助生成，需人工审核」，以区分人工原始记录。

## 三、数据实体（引擎自有表，非 host 表）

- **AI 会话（ai_sessions）**：一次 AI 辅助过程的会话主记录，关联某个实验/笔记/配方与操作用户。
- **AI 交互（ai_interactions）**：会话中的单轮对话，存 prompt、response、model_name、token 消耗、成功/失败状态。
- **AI 审计日志（ai_audit_logs）**：合规用途的调用副本，存操作用户、时间、输入、输出、模型版本，支持管理员导出。

## 四、角色与权限

- **只读角色（read-only）**：SciNote 三类角色之一；**不可调用任何 AI 生成接口**，UI 上隐藏全部 AI 操作按钮。
- **AI 使用权限（can_use_ai_eln?）**：本插件新增的权限判定，替代「是否研究员/管理员」的硬判断，复用 SciNote 角色体系。
- **特性开关（Feature Flag）**：双判定 = `ApplicationSettings#values['ai_eln_enabled']`（DB）且 `AI_ELN_PARSER`（ENV）存在；任一不满足即视为关闭。

## 五、业务对象（沿用 host 术语，不重新定义）

- **实验（experiment）** / **任务（my_module）** / **项目（project）**：host 核心领域对象，本插件只读引用其 id 做关联，不改其结构。
- **配方（recipe / formula）**：多组分材料配方；本插件解析为「SciNote 多组分配方模板 JSON」预览，用户确认后新建配方条目。
- **抽样单元（sampling unit）**：贝叶斯优化的单条训练样本 = 一个 `status=completed` 的 `my_module`；其组分向量来自所关联的配方库 RepositoryRow 数值列，其指标/工艺参数向量来自该 my_module 下的 `ResultTable` 命名列。
- **指标 / 工艺参数（metrics / process params）**：均存于 `my_module` 的 `ResultTable` 命名列（如「介电常数」「固化温度」），由抽取层按列名匹配；结构化、可靠。
- **候选配方（candidate formula）**：贝叶斯优化产出的 draft 配方（默认新建配方库 RepositoryRow，状态 draft、不挂 my_module → **不触发任何库存扣减**），须经用户确认才落业务。
- **图谱（spectrum）**：DSC/TGA 等材料表征图谱（图片/PDF），属待解析附件。
- **GLP 记录自检**：扫描实验记录缺失的合规元数据（试剂批号、设备编号、环境条件等）。

## 六、已锁定的关键决策（详见 ADR-014）

1. 新建**独立** `ai_eln` 引擎，与既有 `ai_protocols` 并列共存；复用其 `LlmClient`，不合并、不替代。
2. 首切片做**地基**（引擎骨架+开关+适配层+三表+审计+抽屉外壳），后续 25 功能挂其上。
3. 配置沿用 **ENV + ApplicationSettings 特性开关**范式，不引入 YAML 配置。
4. 引擎自有表迁移走脚手架 `append_migrations` 模式，**宿主 `db/migrate` 零改动**。
5. 贝叶斯配方优化（AI-501）纳入范围：数据源自 `my_module` 下 `ResultTable`（指标 + 工艺参数）与配方库 Repository（组分）；计算后端 = 纯 ruby（Numo + 自实现 GP），无 python 依赖。
6. 配方/组分质量份映射通过可配置 `RecipeAdapter` 抽象，default = 专属「配方库」Repository（**当前 DEFERRED：用户尚未确定配方表达，default 仅为占位，回填前不得视为最终约定**）；真实约定可经 ApplicationSettings 配置或新增 adapter 子类注入，抽取核心不写死。
