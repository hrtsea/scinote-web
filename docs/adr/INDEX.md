# ADR 索引（主题分组）

> **存放约定**：所有 ADR 仍为**单一平铺**于 `docs/adr/`（`NNNN-slug.md`），本文件只是**导航索引**，不移动任何文件、不改文件名。依据 `docs/agents/domain.md` 与 `docs/开发计划/wechat-gateway/CONTEXT.md`：ADR 单一存放于 `docs/adr/`，新决策一律写入此处，不再建并行 ADR 体系。
>
> 分组与 `docs/开发计划/` 的目录结构一一对应，便于"按子系统找决策"。

---

## A. AI-ELN 引擎 / 配方优化（↔ `开发计划/ai-eln`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0001 | `0001-ai-eln-engine-architecture.md` | AI-ELN Rails Engine 总体架构 |
| 0002 | `0002-ai-audit-logging.md` | AI 操作审计日志 |
| 0003 | `0003-ai-semantic-search-hybrid.md` | AI 混合语义搜索 |
| 0004 | `0004-llm-adapter-layer.md` | LLM 适配器层（Ollama + OpenAI 兼容） |
| 0006 | `0006-formulation-first-class-entity.md` | Formulation 一等实体（配方/组分/属性） |
| 0013 | `0013-ai-protocols-addon.md` | AI Protocols addon |
| 0021 | `0021-bayesian-formulation-optimization.md` | 贝叶斯配方优化 |

## B. 平台核心领域（跨目录基础决策）

| ADR | 文件 | 主题 |
|---|---|---|
| 0007 | `0007-equipment-booking-state-machine.md` | 设备预约状态机 ⚠️ 已被 **0023** 取代（SciNote 无 `EquipmentBooking` 模型，实为 `CalendarEvent`） |
| 0008 | `0008-repository-pattern-core-domain.md` | 核心领域仓库模式 |
| 0009 | `0009-protocol-external-import.md` | 协议外部导入 |
| 0010 | `0010-centralized-permission-model.md` | 集中式权限模型 |
| 0033 | `0033-access-control-refactor-write-side-only.md` | access_control 重构：读写分离，判定权归还宿主（**延伸** 0010） |
| 0011 | `0011-serializer-driven-api.md` | 序列化器驱动 API |
| 0012 | `0012-async-jobs-export-notify.md` | 异步任务 / 导出 / 通知 |
| 0036 | `0036-wopi-unconfigured-graceful-degradation.md` | WOPI 未配置时资产 view/edit 优雅降级（修复全量 500；Accepted） |

## C. addon 规范与注册（↔ `开发计划/addons-config`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0005 | `0005-addon-registration-convention.md` | addon 注册约定 |
| 0020 | `0020-addon-config-schema.md` | addon 配置 schema |
| 0022 | `0022-addon-routes-self-registration.md` | addon 路由自注册 |

## D. 官方功能 / addon 评估（↔ `开发计划/官方功能`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0014 | `0014-esignatures-addon.md` | 电子签名 addon 评估 |
| 0015 | `0015-project-insights-addon.md` | Project Insights addon 评估 |
| 0016 | `0016-item-templates-addon.md` | 条目模板 addon 评估 |
| 0017 | `0017-protocol-version-notifier-addon.md` | 协议版本通知 addon 评估 |
| 0018 | `0018-team-management-assessment.md` | 团队管理评估 |
| 0019 | `0019-integrations-api-assessment.md` | 集成 API 评估 |

## E. WeChat 网关（↔ `开发计划/wechat-gateway`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0023 | `0023-wechat-gateway-addon.md` | WeChat 网关 addon 总体（双通道桥接） |
| 0024 | `0024-task-assignment-semantics.md` | 任务指派语义（F6 = `UserMyModule`） |
| 0025 | `0025-wechat-gateway-command-authorization.md` | 指令权限校验（可见性闸门基座） |
| 0026 | `0026-wechat-gateway-team-scope.md` | Team 作用域 |
| 0027 | `0027-wechat-gateway-no-destructive-commands.md` | 无删除指令 |
| 0028 | `0028-wechat-gateway-target-selection.md` | 目标选择（显式 > 上下文 > 引导） |

## F. 资源申请 / 库存（↔ `addons/eln_ui`）

| ADR | 文件 | 主题 |
|---|---|---|
| 0029 | `0029-resource-application-approvers.md` | 资源申请筛选、可见范围与审批人配置 |
| 0030 | `0030-material-application-is-procurement.md` | 材料类申请＝请购单；终审通过 → 到货验收 → 入库 |
| 0031 | `0031-embed-native-inventories-list.md` | 资源台账内嵌原生 Inventories 列表（不新造外壳）。**V2.0 2026-10-09 换承载**：改由 ResCenter 自己的 Vue app `import` 原生 `repositories/table.vue` 渲染（取代「第二个 Vue app + 挂载点外渲染 + `style.display` 显隐」三条硬约束）；含 `isolate_namespace` 让 addon controller 宿主路由助手失效的实证与修法 |
| 0032 | `0032-receipt-verification-photos-configurable-inspector.md` | 到货验收：照片 ＋ 可配置验货人 ＋ 分批验收 ＋ 未验货阻断（修正 0030 的「验货人沿用终审名单」） |
| 0033 | `0033-access-control-refactor-write-side-only.md` | access_control addon 重构目标形态：读写分离，判定权归还宿主（Proposed） |
| 0034 | `0034-vueify-workspace-list.md` | 工作区列表 Vue 化：**源码归 eln_ui（packs + vue/teams/table.vue）、构建挂宿主 webpack**，SSR props 注入（取代早期的「预打包 blob + Sprockets」方向）。**rev 2026-10-08：由 AG Grid 改为「复刻原生」**（Bootstrap 4 列表格 + 服务端 JSON 分页/排序 + 原生弹窗，文案服务端注入）（Accepted） |
| 0035 | `0035-project-list-column-state-and-pinning.md` | 项目列表（eln_ui）列状态持久化（复用原生 /user_settings/:key 端点，按用户存服务端）＋ 钉列（冻结到该列，sticky 前缀语义）｜含 engine 路由 helper 两个实测坑（Accepted） |
| 0037 | `0037-project-list-v1-gap-batch1.md` | 项目列表（eln_ui）V1 判据硬伤批次一：每页档位[0,20,50,100]、操作列名「操作」、卡片视图、状态口径单一真源（随 07e0fc1d4 落地；Accepted） |
| 0038 | `0038-project-list-v1-gap-batch2.md` | 项目列表（eln_ui）V1 全功能补缺批次二：收藏星标列（复用宿主 favorites）/ 文件夹行专属视觉 / 批量选择+操作（复用宿主 ActionToolbar）/ AG Grid 主题美化（Accepted） |
| 0039 | `0039-project-list-v1-gap-batch3.md` | 项目列表（eln_ui）V1 全功能补缺批次三：**文件夹层级面包屑 + 返回上一层**（spec SCN-7）——后端 `folderNav` 补 `rootUrl`、前端修 ui 拉取丢 query + 渲染面包屑 + 高度链（Accepted） |
| 0040 | `0040-datatable-column-state-migration-and-access-entry.md` | **宿主 DataTable 列状态迁移**：`table.vue` 引入列签名（`colSig`）自愈合，列结构变化自动作废旧状态（排除运行时列 `ag-Grid-ControlsColumn`）；附 access_control「页面级入口」调研（行级 `access` 已就位 / visibility_matrix 系实验页入口 / 列表页无页面级落点，待裁决）（A：Accepted；B：Proposed） |
| 0041 | `0041-row-action-access-modal-native-contract.md` | 行级「访问权限」弹窗按原生契约修：`user_roles` 是**二维元组**不是对象（角色下拉空的真因）/ 候选池随行下发 `assignable_users_url` / 新增成员走 **collection POST `?id=`** 而非 member 路径（后者无 POST 必 404）；附重复实现债：`vue/eln/` 下另一份 `RowActionModal` 未注册 entryList，后续整车复用原生 `AccessModal`（Accepted） |
| 0042 | `0042-split-runtime-db-check-from-build-gate.md` | **构建期 CI 门禁与运行期 DB 依赖解耦**：`access_control.verify!` 按外部依赖拆两半，构建期只跳需DB 的表检查（`SKIP_ACCESS_CONTROL_DB_CHECK`），装饰器探测照跑；否决「跳过整个verify!」/「构建期起 db」/「删门禁」三案，含护栏自证记录（Accepted） |
| 0043 | `0043-i18n-addon-shutdown-dead-reference.md` | 停用 i18n addon 后 `i18n_bundle.js:3` 的 **Sprockets 死引用**导致 `assets:precompile` 整轮构建失败：拆分为宿主 `i18n/locale_sync.js`（保 locale 与服务端对齐，eln_ui/workbench 全部 Vue 页依赖）+ 切换器 UI 随 addon 停用；含 10-07 停用核查漏查Sprockets 资产一路的复盘，与 ADR-0042 适用范围补正（Accepted） |
| 0044 | `0044-addon-routes-all-self-registered.md` | addon 路由全仓库自注册收口：宿主 `config/routes.rb` 对全部 10 个 addon 零残留，常驻守卫 `host_routes_addon_purity_test.rb`；含「控制器名禁前导斜杠」（Rails 7.2 ArgumentError）与「test/runner 环境 Engine.routes=0 ⇒ 断言须走真机 HTTP」两条实证（Accepted） |
| 0045 | `0045-merge-workbench-into-eln-ui.md` | workbench addon 整体并入 eln_ui（其前端 Vue / URL 字面量 / 数据口径本就在 eln_ui，只是空壳 addon）；修 workbench↔eln_ui 跨 addon 硬依赖（单独禁用 eln_ui 会让 `/eln_workbench` 500）（Accepted） |
| 0046 | `0046-addon-settings-helper-forwarding-fix.md` | addon 路由 helper 宿主侧转发修复：Rails route helper 模块**重写 `respond_to?` 且不 consult `respond_to_missing?`** ⇒ method_missing 范本对守卫场景无效；正解 = `config.to_prepare` + 具体 `define_method` 装到 `@path_helpers_module`（Accepted） |
| 0047 | `0047-resgrid-autoheight.md` | ResGrid 默认不传 height ⇒ 走宿主 autoHeight（AG Grid `domLayout: 'autoHeight'`），网格随行数撑开无内部滚动条；height 留作个别长表 override 旋钮（Accepted） |
| 0048 | `0048-workbench-personal-action-center.md` | workbench 个人行动中心（并入 eln_ui 后的页面决策）（Accepted） |
| 0049 | `0049-required-docs-fixed-list.md` | **必传文档固定清单化**：规范清单补种（RequiredDocSeeder + 一次性迁移 + show 懒补种）+ `docs_block` 补稳定 `:id` + 行级上传端点（task_book 退役壳 410）；不建归档闸门（如实记录缺口）（Accepted） |
| 0050 | `0050-attachment-read-links.md` | **附件读取链路与 other 上传接线**：other 累积上传（subhead 建新行，name/type 全自动）+ 预览/下载显式端点 redirect（不下发 signed_id，可读者权限）；宿主 `CheckBlobPermissions` 白名单加 addon 分支（record_type 白名单外一律 403 的发现）；controller 裸 rails_blob_path 踩 _recall ⇒ 全限定（Accepted） |

---

## 平铺时序清单（编号即身份，supersede 依据编号）

0001 · 0002 · 0003 · 0004 · 0005 · 0006 · 0007 ⚠️(→0023) · 0008 · 0009 · 0010 · 0011 · 0012 · 0013 · 0014 · 0015 · 0016 · 0017 · 0018 · 0019 · 0020 · 0021 · 0022 · 0023 · 0024 · 0025 · 0026 · 0027 · 0028 · 0029 · 0030 · 0031 · 0032 · 0033 · 0034 · 0035 · 0036 · 0037 · 0038 · 0039 · 0040 · 0041 · 0042 · 0043 · 0044 · 0045 · 0046 · 0047 · 0048 · 0049 · 0050

共 50 篇。新增 ADR 继续顺延编号（`0051-...`），并补一行到对应主题分组与本清单。
