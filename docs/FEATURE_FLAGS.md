# SciNote 功能开关清单（Feature Flags）

> 本文档由知识图谱分析（`ApplicationSettings` / `ENV` / Team `settings` 三套机制）整理而成，
> 记录各功能开关的判定位置、默认值、当前开启状态与开启方式。架构有重大变化时请重新生成。
>
> 状态标记：**✅ 已开启** / **⬜ 默认关闭（按需开启）**。

## 一、开关机制分类

| 类型 | 判定方式 | 默认值 |
|---|---|---|
| **ENV 全局变量** | 如 `sso_enabled?` → `ENV['SSO_ENABLED'] == 'true'` | 不设置即 `false`（关闭） |
| **`ApplicationSettings`（DB 单条记录）** | `ApplicationSettings.instance.values['<key>']` | 记录为空（`first \|\| new`），**全部默认 `false`** |
| **Team / 模型 `settings` 列** | 如 `shareable_links_enabled?` → `settings['task_sharing_enabled']` | 默认 `false`，需团队设置开启 |

关键事实：`ApplicationSettings` 模型 `instance` 返回 `first || new`，种子数据 `db/seeds.rb`
不写入任何 values，仅 `APP_STTG_*` 环境变量会被 `load_values_from_env` 合并进 `values`
（键自然资源名转小写，**不会**映射到 `forms_enabled` 这类短键）。因此所有依赖
`ApplicationSettings.instance.values['...']` 的功能，未配置前一律关闭。

## 二、已开启的功能

### 2.1 通过迁移开启（ApplicationSettings / DB，均 ✅ `true`）

迁移 `db/migrate/20260830120000_enable_feature_flags.rb` 向 `ApplicationSettings` 记录写入以下键：

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

### 2.2 通过 docker-compose.yml / .env.example 开启（ENV 类，✅ 重启 web 生效）

以下变量已在 `docker-compose.yml` 的 `web` 服务与 `.env.example` 中设为启用值，且 web 容器已重建启动（提交 `0fb364f11`）：

| 变量 | 启用值 | 作用 | 消费位置 |
|---|---|---|---|
| `SCINOTE_SCHEDULER_ENABLED` | `true` | 定时任务总开关 | config/initializers/scheduler.rb |
| `ENABLE_TEMPLATES_SYNC` | `true` | 模板项目同步（依赖调度先开） | scheduler.rb |
| `ENABLE_FLUICS_SYNC` | `true` | Fluics 标签模板同步（依赖调度先开） | scheduler.rb |
| `ACTIVESTORAGE_ENABLE_PDF_PREVIEWS` | `true` | PDF 预览 | config/initializers/active_storage.rb |
| `ACTIVESTORAGE_ENABLE_VIPS` | `true` | Active Storage vips 处理器 | active_storage.rb |
| `CORE_API_V1_ENABLED` | `true` | Core API v1 路由 | config/initializers/api.rb + config/routes.rb |
| `CORE_API_V2_ENABLED` | `true` | Core API v2 路由 | api.rb + routes.rb |
| `CORE_API_KEY_ENABLED` | `true` | Core API Key 认证 | api.rb + app/controllers/concerns/token_authentication.rb |
| `SCINOTE_PWA_DOMAIN_NAME` | `https://pwa.example.com`（占位） | PWA 跨域 CORS | config/initializers/cors.rb |

> 注意：
> - `SCINOTE_PWA_DOMAIN_NAME` 是**域名而非布尔**，当前为占位值，需替换为真实 PWA 来源才能生效。
> - `ACTIVESTORAGE_ENABLE_PDF_PREVIEWS=true` 需容器内已安装 poppler 等预览依赖，否则预览不生成但应用正常运行。
> - `CORE_API_V1/V2_ENABLED` 在 `api.rb` 中以 `ENV[...] || false` 读取，设为任意非空值即开启（推荐写 `true`）。

#### 调度器任务清单（SCINOTE_SCHEDULER_ENABLED）

`SCINOTE_SCHEDULER_ENABLED` 是 **web 进程内 `rufus-scheduler` 单例**的总开关，**无独立 UI、仅 ENV 控制**：代码里没有对应的设置页面或开关按钮，启用只能在 `docker-compose.yml` / `.env` 设 `SCINOTE_SCHEDULER_ENABLED=true` 后**重启 web 服务**；关闭同理。其效果间接体现在已有 UI（右上角通知铃铛、模板静默更新、旧通知自动清除等）。

开启后实际运行的任务（`config/initializers/scheduler.rb`）：

| 任务 | 触发间隔 | 依赖开关 | 作用 / 体现位置 |
|---|---|---|---|
| 模板项目同步 | 12h | `ENABLE_TEMPLATES_SYNC=true` | `TemplatesService.update_all_templates`，模板被静默刷新（无专门提示） |
| Fluics 标签模板同步 | 24h | `ENABLE_FLUICS_SYNC=true` | `LabelPrinters::Fluics::SyncService.sync_templates!`，体现在标签打印机模板列表 |
| 到期提醒（5 类） | 默认 1h（可用 `REMINDER_JOB_INTERVAL` 调整） | — | 项目 / 实验 / 模块(任务) / 仓库条目 / 日历事件到期；向用户发通知（铃铛 + 邮件） |
| WOPI 令牌清理 | 1d | `WOPI_ENABLED=true` | 删除过期 WOPI token（无 UI 感知） |
| 通知清理 | 1d | — | `NotificationCleanupJob` 删除 3 个月前的通知（铃铛列表自动瘦身） |

> 注：`ENABLE_TEMPLATES_SYNC` / `ENABLE_FLUICS_SYNC` 是调度器的子开关，仅在调度器本身开启后才生效。

## 三、仍需额外环境变量才能完全开启的两项

| 功能 | 判定方法 | 依赖的环境变量 | 说明 |
|---|---|---|---|
| protocols.io 导入 | `Protocol.protocols_io_enabled?` | `PROTOCOLS_IO_ACCESS_TOKEN` | 需真实 API 令牌；已在 `.env.example` / `docker-compose.yml` 预留（留空即关闭） |
| AI 协议解析 | `Protocol.ai_parser_enabled?` | `AI_PROTOCOLS_PARSER` | 需解析服务地址；`ai_protocol_parser_enabled` 已由迁移置 `true` |

`docker-compose.yml` 的 `web` 服务与 `.env.example` 均已加入上述两个变量（留空即关闭）。

## 四、默认关闭 / 按需开启的开关（⬜）

**认证 / SSO（依赖 `ApplicationSettings`，需管理员在设置 UI 配置）**
- `okta_enabled?` — `values['okta']['enabled']`
- `azure_ad_enabled?` — `values['azure_ad_apps']`
- `saml_enabled?` — `values['saml']['enabled']`
- `openid_connect_enabled?` — `values['openid_connect']['enabled']`
- `sso_enabled?` — `ENV['SSO_ENABLED'] == 'true'`

**团队级开关**
- `shareable_links_enabled?`（`task_sharing_enabled`）— 默认关闭；存于 `Team#settings` 列，由团队设置 → General → Sharing → "Enable task sharing" 开启（需 `can_manage_team?`）。

**全局 ENV 删除防护开关**
- `Team.deletion_prevention_enabled?` — `ENV['DELETION_PREVENTION_ENABLED'] == 'true'`；开启后暴露团队「Data integrity」设置，可逐团队限制仓库/结果/协议步骤的删除。

**全局 ENV 特性开关（仍默认关闭）**
- `WOPI_ENABLED`（在线编辑）
- `OTEL_ENABLED` / `OTEL_XRAY_ENABLED`（可观测性）
- `CHROMIUM_PATH` / `GROVER_TIMEOUT_MS`（报告 PDF 生成依赖 Chromium，非开关，为路径/数值）

## 五、开启方式汇总

- **ApplicationSettings 类（DB）**：由管理员在团队设置 UI 配置，或运行迁移开启；
  `APP_STTG_*` 环境变量可注入 `values`（键名转小写）。
- **ENV 类**：在 `.env` / `docker-compose.yml` / 编排平台设置对应变量后**重启 web 服务**生效。
- **Team 类**：团队设置页开启 `task_sharing_enabled` 等。

## 六、回滚

```bash
# 撤销 EnableFeatureFlags 迁移，精确移除上述 8 个 DB 键
bin/rails db:rollback

# ENV 类开关回退：将 docker-compose.yml / .env 中对应变量改为 false（或留空）并重启 web
```
