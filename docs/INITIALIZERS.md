# 初始化配置清单 — `config/initializers/`（共 50 项）

> 由 `codebase-memory` 知识图谱索引 + 源码阅读整理。
> 路径基准：`scinote-web/config/initializers/`
> 说明：代码符号、ENV 变量名、类名保留原文；功能说明中文化。

---

## 一、认证与授权（8 项）

| 文件 | 功能说明 |
|---|---|
| `devise.rb` | Devise 认证配置：密码强度（`stretches` 测试环境 1 / 生产 10）、邀请上限 100、确认/锁定/超时策略；会话超时由 `SCINOTE_SESSION_TIMEOUTS_IN` 控制（默认 3h）；邮箱确认由 `enable_email_confirmations` 开关；2FA 锁策略 `:failed_attempts`、最多 10 次尝试；接入 LinkedIn OmniAuth（受 `enable_user_registration` 控制）；Warden 失败钩子处理 Doorkeeper OAuth 跳转。 |
| `doorkeeper.rb` | OAuth2  provider（Doorkeeper）配置：ORM 为 ActiveRecord；仅启用 `authorization_code` 授权流；access token 有效期 2h、支持 refresh token；自定义 token 生成器 `Api::CoreJwt`；资源所有者鉴权 `current_user`。 |
| `omniauth.rb` | OmniAuth 身份联合：通过 `setup` 回调动态注入 Azure AD（`customazureactivedirectory`）、OpenID Connect、Okta、SAML 四种策略的配置（配置存于 `ApplicationSettings`）。各 `*_SETUP_PROC` 在请求时读取 `ApplicationSettings` 填充 client_id/secret/endpoint 等。 |
| `azure_ad.rb` | 启动时（reload）从环境变量 `*_AZURE_AD_APP_ID` 等读取多个 Azure AD 应用配置，写入 `ApplicationSettings#azure_ad_apps`；缺项即报错；未连库则跳过。 |
| `okta.rb` | 从环境变量 `OKTA_CLIENT_ID/SECRET/DOMAIN` 读取 Okta 配置，回写 `ApplicationSettings#okta`；未连库则跳过。 |
| `canaid.rb` | 注册 Canaid 权限引擎：把 `app/permissions/**/*.rb` 及各个 addon 的 permissions 目录加入 `permissions_paths`，建立权限规则来源。 |
| `permissions_policy.rb` | Rails HTTP Permissions-Policy（功能策略）示例，当前全部注释，未启用。 |
| `extends/permission_extends.rb` | `PermissionExtends` 模块：以常量形式定义 Team/Protocol/Form/Report/Project/Experiment/MyModule/Repository/FormResponse 等操作权限字符串，并汇总预定义角色（Owner / NormalUser / Technician / Viewer）的权限集合——权限模型的单一事实来源。 |

## 二、外部服务与集成（11 项）

| 文件 | 功能说明 |
|---|---|
| `active_storage.rb` | Active Storage 配置：启用 PDF（Poppler）/ LibreOffice 预览器、文本抽取分析器、SVG 可变内容类型；`ACTIVESTORAGE_ENABLE_VIPS` 开启 vips 处理器；`Blob` 混入 `ObservableModel` 以记录操作人 `Current.user`；PDF 预览开关 `ACTIVESTORAGE_ENABLE_PDF_PREVIEWS`。 |
| `grover.rb` | Grover（HTML→PDF，基于 Chromium headless）配置：`executable_path` 取 `CHROMIUM_PATH` 或 `./bin/chromium`，超时取 `Constants::GROVER_TIMEOUT_MS`，启动参数禁用 GPU/沙箱。 |
| `wopi_startup_check.rb` | 仅当 `WOPI_ENABLED=true` 且以 Server 模式启动时，校验 WOPI 相关环境变量（`WOPI_DISCOVERY_URL` 等）是否齐全，缺失则 `abort` 阻止启动。 |
| `repositories.rb` | 配置仓库数量限制：`config.x.team_repositories_limit`（`TEAM_REPOSITORIES_LIMIT` 或 `Constants::DEFAULT_TEAM_REPOSITORIES_LIMIT`）与 `config.x.global_repositories_limit`（`GLOBAL_REPOSITORIES_LIMIT`，默认 0=不限）。 |
| `scheduler.rb` | 基于 `rufus-scheduler` 的定时任务（仅 `SCINOTE_SCHEDULER_ENABLED=true`）：模板同步、Fluics 标签模板同步、各类到期提醒 Job、WOPI token 清理、通知清理；带随机抖动避免并发峰值。**无独立 UI、仅 ENV 控制**：开启/关闭都需改 `SCINOTE_SCHEDULER_ENABLED` 并重启 web。 |
| `rubyzip.rb` | 启用 Zip64 支持（`Zip.write_zip64_support = true`），用于大体积导出包。 |
| `opentelemetry.rb` | 可观测性（`OTEL_ENABLED=true` 时加载）：启用全量 Rails 插桩；`OTEL_XRAY_ENABLED` 时启用 AWS X-Ray 的 ID 生成器与传播器。 |
| `silencer.rb` | 用 Silencer 替换 Rails 日志中间件，静默 PDF 生成、健康检查 `/api/health`、`/api/status` 等高频/噪音请求日志。 |
| `rack_attack.rb` | 仅生产环境对 `/api/` 路径按 IP 限流（阈值 `config.x.core_api_rate_limit`，窗口 60s），超限返回 429 并附 RateLimit 头。 |
| `cors.rb` | 当 `SCINOTE_PWA_DOMAIN_NAME` 存在时，插入 `Rack::Cors` 允许 PWA 域跨域访问 `/oauth/token`、`/rails/active_storage/*`、`/api/*`。 |
| `api.rb` | 自定义 Core API 配置（存于 `config.x`）：签名算法 `CORE_API_SIGN_ALG`、token 有效期、签发者、限流、v1/v2 与 API key 启用开关。 |

## 三、业务领域常量与扩展点（5 项）

| 文件 | 功能说明 |
|---|---|
| `constants.rb` | 全局常量 `Constants`：字符串/文本长度上限、查询与分页限制、文件大小限制、图片尺寸、Word 报告版式（twips）、日期格式、颜色、外部 URL（教程/支持/2FA）、Protocols.io 端点与 API 参数、可预览/可编辑文件类型、HTML 净化配置、仓库默认分页/表状态、库存单位等——业务规则的集中常量表。 |
| `extends.rb` | `Extends` 类：可被子模块扩展的枚举/映射注册表（**可变常量**）。含任务状态、报告元素类型、仓库数据类型（14 种值类型映射）、仓库搜索/高级搜索属性、STI 预加载类、API 版本、OmniAuth 提供者、活动类型大表（`ACTIVITY_TYPES`，约 500 项）、活动分组、可通知活动、默认任务流、标签模板 ZPL、外部连接服务白名单、团队自动化观察者配置、团队设置等。 |
| `extends/notification_extends.rb` | `NotificationExtends`：通知类型→收件人模块的映射（`NOTIFICATIONS_TYPES`，含 code）与通知分组（`NOTIFICATIONS_GROUPS`：模块/项目实验/仓库/其他），驱动通知分发。 |
| `report_templates.rb` | 启动时扫描 `app/views/reports/templates` 与 `docx_templates` 目录，将子目录名（或 `name.txt`）登记进 `Extends::REPORT_TEMPLATES` / `Extends::DOCX_REPORT_TEMPLATES`，供报告模板选择。 |
| `asset_url_processor.rb` | 注册 Sprockets CSS 后处理器 `AssetUrlProcessor`，将相对 `url(...)` 重写为经 `asset_path` 解析的资产 URL（处理非 #/data/http 前缀）。 |

## 四、异步任务（1 项）

| 文件 | 功能说明 |
|---|---|
| `delayed_job_config.rb` | `Delayed::Worker` 配置：从环境变量解析失败任务保留、sleep 延迟、最大运行时间、read_ahead、默认队列；`max_attempts=1`（重试交给 ActiveJob）；定义 `high_priority`/`webhooks`/`low_priority` 三个命名队列的优先级。 |

## 五、插件 / 加载器 / 基础设施（8 项）

| 文件 | 功能说明 |
|---|---|
| `addon_loader.rb` | Addon 前端组件加载器（目前主体已注释，仅留占位说明）；用于把 `addons/*/client` 符号链接进 `app/javascript` 并生成聚合配置——当前未启用。 |
| `load_addons_specs.rb` | 测试/开发环境把各 addon 的 `spec` 符号链接、`features` 拷贝进主工程，使 rspec/cucumber 能识别 addon 测试。 |
| `preload_stis.rb` | 非 eager_load 时预加载 `Extends::STI_PRELOAD_CLASSES`（单表继承类：LinkedRepository、SoftLockedRepository、各类 Form 字段值等），避免首次请求时解析 STI 造成的 N+1/延迟。 |
| `js_routes.rb` | `JsRoutes` 配置（把 Rails 路由暴露给 JS），当前为默认空配置。 |
| `kaminari_config.rb` | Kaminari 分页配置：默认每页 10、最大 100。 |
| `active_model_serializer.rb` | ActiveModelSerializers 配置：适配器 `:json_api`、key 不做 camelize 转换（`key_transform :unaltered`）。 |
| `analyzable_no_touching.rb` | 给 `ActiveStorage::Blob::Analyzable#analyze` 包一层 `ActiveRecord::Base.no_touching`，避免分析文件时触碰 `updated_at`/触发回调。 |
| `session_store.rb` | Rails 会话存储配置（标准，cookie 存储）。 |

## 六、Rails 标准初始化器（其余项，多为默认/约定）

以下为 Rails 框架默认或约定式初始化器，通常无需修改：

| 文件 | 功能说明 |
|---|---|
| `action_mailer.rb` | Action Mailer 默认配置（投递方式、默认发件人、SMTP 等）。 |
| `application_controller_renderer.rb` | 配置 `ApplicationController` 的离请求渲染器（用于邮件/后台任务中渲染视图）。 |
| `assets.rb` | Assets Pipeline 配置（预编译文件清单、摘要、JS 压缩器等）。 |
| `backtrace_silencers.rb` | 配置异常回溯过滤（隐藏框架内部栈帧）。 |
| `content_security_policy.rb` | HTTP Content-Security-Policy 配置（当前多为注释示例）。 |
| `cookies_serializer.rb` | Cookie 序列化方式（默认 `:json`）。 |
| `filter_parameter_logging.rb` | 日志参数过滤（密码等敏感字段脱敏）。 |
| `i18n.rb` | 国际化配置（默认 locale、回退、load_path）。 |
| `inflections.rb` | 单复数不规则变形规则（inflections）。 |
| `mime_types.rb` | 注册的 MIME 类型映射。 |
| `wrap_parameters.rb` | 默认把 JSON 请求参数包装进 `params[:<model>]`（ActiveRecord 约定）。 |
| `new_framework_defaults_5_1.rb` … `new_framework_defaults_7_2.rb` | Rails 升级时生成的「新版框架默认值」固定文件（5.1/5.2/6.0/6.1/7.0/7.1/7.2 共 7 个），用于按版本钉住框架默认行为，便于平滑升级。 |

---

## 七、关键环境变量速查（按初始化器归类）

- **认证/SSO**：`SCINOTE_SESSION_TIMEOUTS_IN`、`SCINOTE_USERS_CONFIRM_WITHIN`、`DISABLE_LOCAL_PASSWORDS`、`LINKEDIN_KEY/SECRET`、`OKTA_*`、`*_AZURE_AD_*`、`OTEL_ENABLED`、`OTEL_XRAY_ENABLED`
- **API/限流**：`CORE_API_SIGN_ALG`、`CORE_API_TOKEN_TTL`、`CORE_API_RATE_LIMIT`、`CORE_API_V1/V2_ENABLED`、`CORE_API_KEY_ENABLED`
- **CORS/PWA**：`SCINOTE_PWA_DOMAIN_NAME`
- **存储/预览**：`ACTIVESTORAGE_ENABLE_PDF_PREVIEWS`、`ACTIVESTORAGE_ENABLE_VIPS`、`CHROMIUM_PATH`
- **仓库**：`TEAM_REPOSITORIES_LIMIT`、`GLOBAL_REPOSITORIES_LIMIT`
- **调度**：`SCINOTE_SCHEDULER_ENABLED`、`ENABLE_TEMPLATES_SYNC`、`ENABLE_FLUICS_SYNC`、`REMINDER_JOB_INTERVAL`、`WOPI_ENABLED`
- **DelayedJob**：`DELAYED_WORKER_DESTROY_FAILED_JOBS`、`DELAYED_WORKER_SLEEP_DELAY`、`DELAYED_WORKER_MAX_RUN_TIME`、`DELAYED_WORKER_READ_AHEAD`、`DELAYED_WORKER_DEFAULT_QUEUE_NAME`

---

*本清单与知识库 ADR（`manage_adr(mode="get")`）及 `docs/ARCHITECTURE_DECISIONS.md` 互为补充。初始化器变更需重启服务方可生效。*
