# SciNote 功能开关清单（Feature Flags）

> 本文档由知识图谱分析（`ApplicationSettings` / `ENV` / Team `settings` 三套机制）整理而成，
> 记录各功能开关的判定位置、默认值与开启方式。架构有重大变化时请重新生成。

## 一、开关机制分类

| 类型 | 判定方式 | 默认值 |
|---|---|---|
| **ENV 全局变量** | 如 `sso_enabled?` → `ENV['SSO_ENABLED'] == 'true'` | 不设置即 `false`（关闭） |
| **`ApplicationSettings`（DB 单条记录）** | `ApplicationSettings.instance.values['<key>']` | 记录为空（`first \|\| new`），**全部默认 `false`** |
| **Team / 模型 `settings` 列** | 如 `shareable_links_enabled?` → `settings['task_sharing_enabled']` | 默认 `false`，需团队设置开启 |

关键事实：`ApplicationSettings` 模型 `instance` 返回 `first || new`，种子数据 `db/seeds.rb`
不写入任何 values，仅 `APP_STTG_*` 环境变量会被 `load_values_from_env` 合并进 `values`
（键名转小写，**不会**映射到 `forms_enabled` 这类短键）。因此所有依赖
`ApplicationSettings.instance.values['...']` 的功能，未配置前一律关闭。

## 二、已开启的功能（本次通过迁移开启）

迁移 `db/migrate/20260830120000_enable_feature_flags.rb` 向 `ApplicationSettings` 记录写入以下键（均 `true`）：

| 类别 | 键 | 对应判定方法 | 文件 |
|---|---|---|---|
| 仓库/库存高级能力 | `stock_management_enabled` | `RepositoryBase.stock_management_enabled?` | app/models/repository_base.rb |
| 仓库/库存高级能力 | `repository_row_connections_enabled` | `RepositoryBase.repository_row_connections_enabled?` | app/models/repository_base.rb |
| 仓库/库存高级能力 | `equipment_booking_enabled` | `Repository.equipment_booking_enabled?`（同时开启日历事件） | app/models/repository.rb |
| 协议/化学结构 | `protocol_content_locking_enabled` | `Protocol.content_locking_enabled?` | app/models/protocol.rb |
| 协议/化学结构 | `ai_protocol_parser_enabled` | `Protocol.ai_parser_enabled?`（还需 ENV） | app/models/protocol.rb |
| 表单/存储位置/用户组 | `forms_enabled` | `Form.forms_enabled?` | app/models/form.rb |
| 表单/存储位置/用户组 | `storage_locations_enabled` | `StorageLocation.storage_locations_enabled?` | app/models/storage_location.rb |
| 表单/存储位置/用户组 | `user_groups_enabled` | `UserGroup.enabled?` | app/models/user_group.rb |

> 说明：`reminders_enabled?` 依赖 `stock_management_enabled?`，库存管理开启后提醒随之可用。

## 三、仍需额外环境变量才能完全开启的两项

| 功能 | 判定方法 | 依赖的环境变量 | 说明 |
|---|---|---|---|
| protocols.io 导入 | `Protocol.protocols_io_enabled?` | `PROTOCOLS_IO_ACCESS_TOKEN` | 需真实 API 令牌；已在 `.env.example` / `docker-compose.yml` 预留 |
| AI 协议解析 | `Protocol.ai_parser_enabled?` | `AI_PROTOCOLS_PARSER` | 需解析服务地址；`ai_protocol_parser_enabled` 已由迁移置 `true` |

`docker-compose.yml` 的 `web` 服务与 `.env.example` 均已加入上述两个变量（留空即关闭）。

## 四、其他默认关闭的开关（本次未开启）

**认证 / SSO（依赖 `ApplicationSettings`，需管理员在设置 UI 配置）**
- `okta_enabled?` — `values['okta']['enabled']`
- `azure_ad_enabled?` — `values['azure_ad_apps']`
- `saml_enabled?` — `values['saml']['enabled']`
- `openid_connect_enabled?` — `values['openid_connect']['enabled']`
- `sso_enabled?` — `ENV['SSO_ENABLED'] == 'true'`

**团队级开关**
- `shareable_links_enabled?`（`task_sharing_enabled`）— 默认关闭
- `Team.deletion_prevention_enabled?` — `ENV['DELETION_PREVENTION_ENABLED'] == 'true'`

**全局 ENV 特性开关（initializers 中默认关闭）**
- `WOPI_ENABLED`（在线编辑）
- `SCINOTE_SCHEDULER_ENABLED`（定时任务：提醒/同步/清理）
- `ENABLE_TEMPLATES_SYNC` / `ENABLE_FLUICS_SYNC`（需调度先开启）
- `OTEL_ENABLED` / `OTEL_XRAY_ENABLED`（可观测性）
- `ACTIVESTORAGE_ENABLE_PDF_PREVIEWS` / `ACTIVESTORAGE_ENABLE_VIPS`
- `CORE_API_V1_ENABLED` / `CORE_API_V2_ENABLED` / `CORE_API_KEY_ENABLED`（路由门控）
- `SCINOTE_PWA_DOMAIN_NAME`（PWA CORS）
- `CHROMIUM_PATH` / `GROVER_TIMEOUT_MS`（报告 PDF 生成依赖 Chromium）

## 五、开启方式汇总

- **ApplicationSettings 类（DB）**：由管理员在团队设置 UI 配置，或运行迁移开启；
  `APP_STTG_*` 环境变量可注入 `values`（键名转小写）。
- **ENV 类**：在 `.env` / `docker-compose.yml` / 编排平台设置对应变量后**重启服务**。
- **Team 类**：团队设置页开启 `task_sharing_enabled` 等。

## 六、回滚

```bash
bin/rails db:rollback   # 撤销 EnableFeatureFlags 迁移，精确移除上述 8 个键
```
