# 架构决策记录 — scinote-web（SciNote 电子实验记录本）

> 由 codebase-memory 知识图谱自动生成。
> 工程标识：C-Users-Administrator-CodeBuddy-20260829210627
> 图谱规模：16,158 个节点 / 46,071 条边（全量索引，8 种语言，0 个文件跳过）。

## 一、系统概览
- **类型**：基于 Ruby on Rails 的**电子实验记录本（ELN, Electronic Lab Notebook）** Web 应用。
- **主要语言**：Ruby（1,676 个文件），前端为 Vue 2/3 单页应用层（372 个 `.vue`），另有 JavaScript（275）、SCSS（147）。
- **可观的配置面**：50 个初始化配置、342 个数据库迁移 —— 属于长期、持续维护的大型项目。

## 二、分层结构（由图谱推导）
- `app` 是主导核心：高 fan-in（344 入 / 51 出）—— 系统的中央枢纽。
- `db`（模型 + 迁移）被 `app` 调用 290 次 —— 典型的以 ActiveRecord 为中心的「胖模型」架构。
- `lib`（fan-in 2 / fan-out 19）作为低层工具/基础设施层（Rack 中间件、i18n、rake 任务、active_storage 扩展）。
- `config` 与 `test`/`spec` 为入口/叶子层，仅有出站调用。
- `Makefile` 具有高 fan-in（15 入）—— 构建/运维编排集中于此。

## 三、关键架构决策（ADR）
### ADR-001：Repository（自定义表）模式是核心领域模型
- 依据：`RepositoryRowService#render` 是全局 fan-in 最高的函数（819 个调用方），且 `repository_*` 聚类是内聚性最强的组之一。
- `Repository`/`RepositoryRow`/`RepositoryColumn`/值类型家族（repository_text_value、repository_list_value、repository_stock_value 等）构成数据模型的骨干。
- 影响：对仓库值渲染/序列化的改动影响面最广 —— 应作为**稳定性关键子系统**对待。

### ADR-002：协议从外部源导入（Protocols.io）
- 依据：`ProtocolImporters::ProtocolsIo::V3::StepComponents#name`（421）、`ExternalProtocolsController#new`（232），以及 `utilities/protocol_importers`、`services/protocol_importers`、`protocol_importers_v2/v3` 目录。
- 系统支持多版本协议导入；需在各导入器版本间保持向后兼容。

### ADR-003：权限模型为「角色 + 用户分配」的集中式设计
- 依据：庞大的 `permissions/` 目录（13 个文件，按领域实体逐一划分）、`PermissionError`/`readable_by_user` 聚类，以及 `user_roles` + `user_assignments` + `team_assignments`。
- 权限按实体显式建模（asset、experiment、project、repository、result、step、team、storage_location、form 等）。
- 影响：新增领域实体必须配套对应的 `permissions/<实体>.rb` 及 user_role 权限集合，否则将处于无防护状态。

### ADR-004：序列化器驱动 API 与导出输出
- 依据：57 个序列化器文件；`Lists::MyModuleSerializer#attributes`（163）是热点函数；重度使用 `active_model_serializers`。
- 模块/仓库的 JSON 形态由序列化器生成 —— 应将序列化逻辑保持在控制器之外。

### ADR-005：导出、通知、提醒使用异步作业
- 依据：26 个 job；`repository_*_zip_export_job`、`team_zip_export_job`、通知/提醒 job，后端为 `delayed_job`。
- 长耗时任务（导出、PDF 预览、提醒）被推入 DelayedJob —— 不应阻塞请求路径。

## 四、复杂度热点（维护风险）
| fan_in | 符号 | 风险说明 |
|---|---|---|
| 819 | `LabelTemplates::RepositoryRowService#render` | 触及每个仓库行的渲染；改动波及面极广 |
| 421 | `ProtocolImporters::ProtocolsIo::V3::StepComponents#name` | 与外部格式强耦合 |
| 243 | `BiomoleculeToolkitClient#create` | 外部服务客户端；存在网络/可用性风险 |
| 228 | `ModelExporters::TeamExporter#team` | 导出面大 |
| 177 | `SmartAnnotations::TagToHtml#parse` | 核心文本/注解转换；对 XSS 转义敏感 |

## 五、功能聚类（高内聚模块）
1. 仓库行渲染 + 过滤 + 智能注解（render / repository_rows / repository_row / value / tag_to_html）。
2. 协议导入导出 + 步骤 + 结果（protocol / step / name / result / custom_auto_link）。
3. 团队 / 项目 / 实验 / 模块层级（team / project / merge / experiment / my_module）。
4. 权限 + `readable_by_user` 校验。
5. 资源/二进制/元数据存储（blob / metadata / filename / content_type）。

## 六、后续开发的防护建议
- 将 `repository_*` 与 `permissions/*` 视为稳定性关键区域；重构前先补充刻画性测试。
- 新增实体：按约定同时补齐 模型 + 序列化器 + 控制器 + 权限文件 + factory + spec（图谱显示它们按约定强耦合）。
- 导出/通知逻辑应放在 `app/jobs` 与 `app/services`，而非控制器中。
- `parse_partial` 覆盖缺口存在于 Dockerfile、Makefile 与 `.scss` 文件 —— 均非核心；核心 Ruby/Vue 覆盖完整（0 跳过）。

---

*本文档为 codebase-memory 工程库中持久化 ADR 的镜像
（`manage_adr(mode="get")` 可读）。发生重大架构变更后请重新生成。*
