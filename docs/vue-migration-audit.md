# Vue 化迁移审计清单（scinote-web）

> 生成日期：2026-10-10（v2，partial-aware 重扫；v2.1 加可勾选 `迁移状态` 列 + 后端 `Lists::/AMS` 映射；v2.2 修正 `teams/show.js` 对 `initRemoveUsers` 死代码的误记）
> 方法：扫描 `app/views/**/*.erb`（**含 partial**）全部 `javascript_include_tag 'vue_*`/`'eln_*`，
> 再**反向追踪 `render partial` 链**，把"vue 标签藏在 partial"的整页动作也归入 VUE。
> 分类：
> - **VUE**：整页（或经 partial）引用 Vue 入口，且无非页面级 Gen-1 协处理器
> - **MIXED**：整页同时引用 Vue 入口与 jQuery/库 pack（jQuery 残留待清）
> - **NONVUE**：无任何 Vue 入口（纯 HTML 或 jQuery/库）
> - 判定信号：ERB 内 `javascript_include_tag` 包名 + `render partial` 传递闭包
> - v1→v2 修正：初版只扫顶层 `.html.erb`，漏掉 partial 内的 vue 岛（与指南第5轮盲区一致）；
>   本次补齐后 `dashboards/show`、`users/sessions/new`、`users/passwords/{new,edit}` 由 NONVUE 改 VUE。
> - 后端 `Lists::/AMS` 来自 `app/controllers/**` + `app/services/lists/**` 实查（非推断）。
> - 数据来源：`codebase-memory-mcp` 索引 + 原生检索 + 全量 `render partial` 反向追踪 + `Lists::` 用法 grep

## 总览（v2 修正后）

| 指标 | 数量 | 说明 |
|---|---|---|
| 整页动作总数（app/views `*.html.erb`，去噪声） | **109** | 指南口径 113 = 本表 109 + 4 个 addon/`.json.erb` 页 |
| VUE（已完整 Vue 化） | **41** | v1=35 → +4 partial 岛页 + `teams/new`（本次已迁）+ `teams/show`（本次收口） |
| MIXED（Vue 已挂，jQuery 残留） | **21** | 见 §2，附 `迁移状态` 看板列 |
| NONVUE（未 Vue 化） | **47** | = 约 30 非页面基础设施 + 约 17 实质功能页（§3） |

> 看板用法：§2 / §3 的 `迁移状态` 列填 `todo` / `doing` / `done`，可直接编辑跟踪。

## 1. `teams` controller（重点核对，本次已收口）

| 动作 / URL | 视图 | 状态 | 挂载 pack | 后端 Lists::/AMS | 迁移状态 |
|---|---|---|---|---|---|
| `index` | `users/settings/teams/index.html.erb` | VUE ✅ | `vue_teams_table` | `Lists::TeamsService` + `Lists::TeamSerializer` | done |
| `members` | `users/settings/teams/members.html.erb` | VUE ✅ | `vue_team_members` | `Lists::TeamsService`（成员子查询） | done |
| `data_integrity` | `users/settings/teams/data_integrity.html.erb` | VUE ✅ | `vue_team_preferences` | `Team`/`User` AMS | done |
| `show` | `users/settings/teams/show.html.erb` | **VUE ✅** | `vue_team_preferences` | `Lists::TeamsService` + `Lists::TeamSerializer`（team 设置明细） | done |
| `new` | `users/settings/teams/new.html.erb` | **VUE ✅（本次迁移）** | `vue_team_new` | 原生 `<form>` 提交，控制器零改动 | done |

→ 5 动作 = **5 VUE（index/members/data_integrity/new/show）**。
`new` 已改为 Vue 岛（原生 `<form>` 提交，控制器零改动）；`show` 残留 jQuery `users/settings/teams/show.js`
（经核对 `show.html.erb`：仅 `.inline-init-handler` 描述 inline-edit 仍在；`#users-table`/`.tinymce-view`/`.users-datatable`/
`[data-action='submit-role']`/邀请弹窗/删除成员均已随成员管理拆页到 `members`（vue_team_members）而失效，其中
`initRemoveUsers`（删除成员）实为**死代码**——其 jQuery 触发器随删除成员功能迁至 Vue 成员页（vue_team_members），不再存活于任何页面。**2026-10-10 已修剪**：仅保留 `initNameUpdateEvent`，
删除 `initEditDescription`/`initUsersTable`/`initUpdateRoles`/`initRemoveUsers`（死代码，已修剪）/`initReloadPageAfterInviteUsers` 及
`usersDatatable` 全局变量）。

> **2026-10-10 收口 `show`**：删除页面级 jQuery 协处理器 `users/settings/teams/show.js`，其"改名同步面包屑/团队切换器"逻辑已移入 `app/javascript/vue/team_preferences/container.vue`（`mounted` 监听全局 `inline_editing.js` 冒泡的 `inlineEditing:fieldUpdated`，`unmounted` 配对移除）；`show` 现归 **VUE**，`teams` controller 全部 5 动作完成 Vue 化。

## 2. MIXED 页面看板（21，已 Vue 化、jQuery 残留待清）

优先级：P0=核心编辑器残留 / P1=列表-详情残留 / P2=表单或次级页 / P3=仅库（pdf_js 等）残留

| Controller / 动作 | 挂载 pack（Vue + jQuery/库） | 优先级 | 迁移状态 | 后端 Lists::/AMS（实查） |
|---|---|---|---|---|
| `protocols/show` | `vue_protocol` + `handsontable.full`, `pdf_js` | **P0** | todo | 编辑器：非 Lists 列表；`Protocol` + `Step`/`ProtocolSerializer`（AMS） |
| `results/index` | `vue_results` + `handsontable.full`, `pdf_js` | P1 | todo | `Result` 列表（`Lists::ResultsService` 待确认）+ `ResultSerializer` |
| `result_templates/index` | `vue_results` + `handsontable.full`, `pdf_js` | P1 | todo | `ResultTemplate` 列表（后端 service 待确认） |
| `repositories/show` | `vue_components_action_toolbar`, `vue_repository_search`, `vue_import_repository_modal`, `vue_components_repository_item_error_sidebar` + `repositories/repository_datatable`, `repositories/show`, `inputmask`, `emoji_button`, `pdf_js` | P1 | todo | `Lists::RepositoryRowsService` + `Lists::RepositoryRowSerializer`（无读权限→`PrivateRepositoryRowSerializer`） |
| `my_modules/protocols` | `vue_protocol`, `vue_my_module_show`, `vue_legacy_access_modal` + `my_modules/protocols`, `handsontable.full`, `inputmask`, `emoji_button`, `my_modules/pwa_mobile_app`, `pdf_js` | P1 | todo | `Lists::ProtocolsService` / `Protocol`+`Step` AMS（模块内协议） |
| `protocols/index` | `vue_protocols_list` + `protocols/index`, `handsontable.full`, `assets/wopi/create_wopi_file`, `pdf_js` | P1 | todo | `Lists::ProtocolsService` + `Lists::ProtocolSerializer` |
| `shareable_links/my_module_results_show` | `vue_shareable_results_show` + `handsontable.full`, `shared/file_preview`, `pdf_js` | P2 | todo | `Lists::RepositoryRowsService` + `PrivateRepositoryRowSerializer`（共享上下文） |
| `shareable_links/my_module_protocol_show` | `vue_shareable_protocol_show` + `handsontable.full` | P2 | todo | `Protocol`+`Step` AMS（只读共享） |
| `users/registrations/edit` | `vue_user_registration_edit` + `croppie` | P2 | todo | `User` AMS（表单，非列表） |
| `users/settings/teams/show` | `vue_team_preferences` | P2 | **done（已收口，见 §1；jQuery 协处理器已删，同步逻辑移入 team_preferences.vue）** | `Lists::TeamsService` + `Lists::TeamSerializer`（team 设置明细） |
| `gene_sequence_assets/edit` | `vue_components_open_vector_editor` + `i18n_bundle`, `jquery_bundle`, `vendor/ove/ove.js` | P2 | todo | 无列表（OVE 编辑器）；`OpenVectorEditorService` |
| `experiments/canvas` | `vue_experiment_description_modal`, `vue_legacy_access_modal`, `vue_legacy_new_task_modal` + `experiments/show`, `eventPause-min`, `projects/canvas` | P2 | todo | `Lists::ExperimentsService` + `Lists::ExperimentSerializer`（画布加载实验） |
| `experiments/index` | `vue_experiments_list` + `pdf_js` | P3 | todo | `Lists::ExperimentsService` + `Lists::ExperimentSerializer` |
| `experiments/module_archive` | `vue_components_action_toolbar`, `vue_legacy_access_modal` + `projects/canvas`, `my_modules/archived` | P3 | todo | `Lists::MyModulesService`（archived）+ `Lists::MyModuleSerializer` |
| `my_module_reports/index` | `vue_my_module_reports` + `pdf_js` | P3 | todo | `ReportsService` / `MyModuleReports`（报告列表，待确认确切 service） |
| `my_modules/archive` | `vue_my_module_archive` + `handsontable.full`, `pdf_js` | P3 | todo | `Lists::MyModulesService`（archived）+ `Lists::MyModuleSerializer` |
| `my_modules/index` | `vue_my_modules_list` + `pdf_js` | P3 | todo | `Lists::MyModulesService` + `Lists::MyModuleSerializer` |
| `protocol_report_templates/index` | `vue_protocol_report_templates` + `pdf_js` | P3 | todo | `ProtocolReportTemplate` 列表（后端 service 待确认） |
| `reports/index` | `vue_reports_table` + `pdf_js` | P3 | todo | `Lists::ReportsService` + `Lists::ReportSerializer` |
| `scinote/eln_ui/res_center/index` | `eln_res_center` + `css/.js`（构建产物伪包） | P3 | todo | 自定义 `eln_res_center`（非 Lists） |
| `scinote/workbench/workbench/index` | `eln_workbench` + `css/.js` | P3 | todo | 自定义 `eln_workbench`（非 Lists） |
| `layouts/application` | `vue_navigation_navigator`, `vue_navigation_top_menu`, `vue_legacy_datetime_picker`, `vue_components_repository_item_sidebar` + 全局 jQuery 包 | P3（全局） | todo | N/A（全局布局，最后处理） |

## 3. 实质非 Vue 功能页面（约 15–17，需整页迁移）

> 多为新功能 / 设置 / 报告 / 搜索页，**非 Lists:: 列表页**，故 `后端` 列标对应 service（无 `Lists::`）。

| Controller / 动作 | 优先级 | 迁移状态 | 后端（非 Lists::） |
|---|---|---|---|
| `scinote/ai_protocols/protocol_generator/new` | **P0**（新功能） | todo | `ProtocolGeneratorService`（确切名待查）/ `ProtocolSerializer` |
| `scinote/ai_protocols/protocol_generator/preview` | **P0**（新功能） | todo | 同上（预览渲染） |
| `scinote/project_insights/insights/index` | P1 | todo | `ProjectInsightsService`（待查） |
| `scinote/access_control/visibility_matrix/show` | P1 | todo | 自定义 `AccessControl`（无 Lists::） |
| `scinote/addon_settings/addons/edit` | P2 | todo | `AddonSettingsService`（待查） |
| `qa_tools/design_elements/index` | P2 | todo | 自定义（无 Lists::） |
| `qa_tools/activity_statistics/index` | P2 | todo | 自定义（无 Lists::） |
| `protocol_importers/templates/protocol_description` | P2 | todo | `ProtocolImporters::{Search,Import}ProtocolService` |
| `protocol_importers/templates/step_description` | P2 | todo | 同上 |
| `reports/report` | P2（报告渲染） | todo | `MyModuleReports::GenerateReportService` |
| `reports/export` | P2 | todo | 报告导出 service |
| `reports/templates/scinote_template/footer` | P2 | todo | 模板渲染（无 Lists::） |
| `reports/templates/scinote_template/header` | P2 | todo | 模板渲染（无 Lists::） |
| `users/settings/account/connected_accounts/index` | P2 | todo | OAuth `ConnectedAccount`（无 Lists::） |
| `search/new` | P3 | todo | 搜索 service（待查） |
| `protocols/print` | P3（打印视图） | todo | `Protocol`+`Step` AMS（打印渲染） |

> v2 已从本表移除 `users/settings/teams/new`（已迁 VUE）与 `dashboards/show`（经 partial 实为 VUE）。
> 列表为重点实质页，非穷举；精确计数以"总览"的约 17 为准。

## 4. 非页面基础设施（NONVUE 中应剔除，不计入迁移范围）

- **layouts（8）**：`layouts/fluid`, `layouts/main`, `layouts/mailer`, `layouts/reports/template_values_editor`,
  `layouts/reports/footer_header`, `layouts/shareable_links`(JQUERY), `layouts/sign_in_halt`(JQUERY), `layouts/protocols/print`(JQUERY)
- **errors（3）**：`errors/403`, `errors/404`, `errors/422`
- **doorkeeper / OAuth（3）**：`doorkeeper/authorizations/{show,new,error}`
- **users/mailer（6）**：`confirmation_instructions`, `general_notification`, `invitation_instructions`, `notification`, `reset_password_instructions`, `unlock_instructions`
- **auth 流程（剩余 NONE，4）**：`users/sessions/{two_factor_auth,two_factor_recovery}`, `users/unlocks/new`, `users/invitations/new`
  - ⚠ 已 Vue 化（经 partial 岛，不计入迁移）：`users/sessions/new`（`login_disclaimer`→`vue_login_disclaimer` + `linkedin_sign_in_links`→`vue_linkedin_sign_in`）、
    `users/passwords/{new,edit}`（`users/sessions/login_disclaimer`→`vue_login_disclaimer`）
- **营销页 promo（4）**：`equipment_bookings/promo`, `forms/promo`, `label_templates/promo`, `users/settings/user_groups/promo`
- **导出状态页（2）**：`team_zip_exports/report`, `zip_exports/file_expired`
- **全局 chrome（不翻页分类）**：`shared/navigation/_breadcrumbs`（`vue_navigation_breadcrumbs`）、
  `shared/file_preview/_content`（`vue_open_locally_menu`）、`shared/_repository_item_relationships_modal`
  （`vue_components_repository_item_relationships`）—— 属 layout/modal 级，依指南"全局布局最后处理"原则单列。

> v2 已从"基础设施"剔除 9 个非 app 页面噪声：`.codebuddy/skills/apply-stack-conventions/assets/snippets/{tailwind_component,turbo_frame}`、
> `app/components/reports/*_input_component`（7 个 ViewComponent 模板）—— 它们不是整页动作。

## 5. 迁移策略提示

- 列表类页优先走 **Vue3 + AG Grid** 栈（复用 `shared/datatable`，见 ADR-0035），后端对齐 `Lists::XxxService` + AMS。
- 混合页的 `handsontable.full` 残留多为表格**内联编辑**，可保留为库（非整页 jQuery）；仅 `repositories/show` 的
  `repositories/repository_datatable` 是旧 DataTables 协议，属于真正的迁移对象。
- `layouts/application` 全局布局已含 Vue 导航（`vue_navigation_*`），剩余 jQuery 为全球基础设施，应最后处理。
- 判定"是否已 Vue 化"的可靠信号：ERB 内是否出现 `javascript_include_tag 'vue_*` / `'eln_*`，**且需追踪 `render partial`**
  （vue 标签可能藏在 partial 中，如 `dashboards/show`、`users/sessions/new` 等）。
- 与权威指南 `docs/frontend-vue3-migration.md` 的关系：本表为其**增量补充**（侧重 `teams` controller 拆解与 partial-aware 重扫），
  以指南为唯一真相源；两处数字口径差异见"总览"说明。
