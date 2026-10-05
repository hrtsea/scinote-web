# WeChat / WeCom → SciNote Gateway Addon

进程内 Rails Engine（`Scinote::WechatGateway`），把微信 / 企业微信消息落成 SciNote 实验记录，支持组长派任务。双通道（iLink 私聊 + 企微群聊）统一收敛到同一写入层。设计依据见 `docs/adr/0023-wechat-gateway-addon.md` 与 `F:\eln开发\wechat_to_elabftw\docs\WECHAT-SCINOTE-PLAN.md`。

## 启用（零入侵）

宿主 `Gemfile` 加一行（注释即禁用，启动正常、路由 404，无崩溃）：

```ruby
gem 'scinote_wechat_gateway', path: 'addons/wechat_gateway'
```

路由由 `engine.rb` 的 initializer 自挂载到 `/wechat_gateway`，宿主 `config/routes.rb` 不动。`WECHAT_GATEWAY_ENABLED=false` 可整体关闭。

## 环境变量

| 变量 | 作用 |
|---|---|
| `WECHAT_GATEWAY_ENABLED` | `true`(默认)/`false` 总开关 |
| `WECOM_TOKEN` / `WECOM_ENCODING_AES_KEY` / `WECOM_CORPID` | 企微回调验签 + AES-256-CBC 解密（见 plan §9） |
| `ILINK_TOKEN` / `ILINK_BASE_URL` | iLink bot 私聊通道凭证 |
| `WECHAT_GATEWAY_PROJECT_ID` | 微信录入的默认目标项目 ID（整数主键）。写入层 `scinote_service_writer` 据此解析 `Project`+`team`，**绑定用户须对该项目有创建实验权限**；未配置则 `create_experiment` 抛清晰错误 |
| `VISION_ENDPOINT` | 本地视觉模型 sidecar 的 HTTP 端点（POST 图片字节 → `{text}`）。配置后图片消息自动识别并把文本写入正文；未配置则仅作为附件（Ticket 05） |
| `WECHAT_GATEWAY_AI_ENABLED` | `true` 开启 AI 结构化抽取（F12）；默认 `false` |
| `AI_ENDPOINT` / `AI_API_KEY` / `AI_MODEL` | OpenAI 兼容 LLM 端点/密钥/模型（默认 `deepseek-chat`）。开启后文本消息经 LLM 抽取为配方 schema，正文保留原文 + 标「需人工审核」，并尝试落 `ai_eln` `Formulation`（Ticket 06） |

## 路由

| 路径 | 通道 | 说明 |
|---|---|---|
| `/wechat_gateway/wecom/callback` | 企微 | GET 校验 URL；POST 收消息（XML 加密） |
| `/wechat_gateway/ilink/callback` | iLink | POST 收私聊消息 |
| `/wechat_gateway/bind/confirm` | 备用 | HTTP 绑定确认（主路径为私聊 `/bind <码>`） |

## 绑定流程（F3/F8，一次性绑定码，非 OAuth）

1. 用户在 SciNote 设置页生成绑定码（绑到生成时 `current_user`，10 分钟过期，一次性）。
2. 微信 / 企微发 `/bind <码>`。
3. addon 校验码有效且未过期 → 写 `wechat_user_bindings(wechat_id, platform, scinote_user_id)`。
4. 此后记录落到该 SciNote 用户名下（`created_by` 真实，审计链正确）。

绑定码存 `Rails.cache`，绑定关系落 `wechat_user_bindings` 表（迁移 `20260910120000`）。无设置页 UI 时可用 `BindController#confirm` 的 HTTP 入口。

## 指令

命名规律：`<动词><实体>`，动词只有四个 —— `new`（建）/ `set`（设为当前）/ `get`（查看当前）/ `list`（列举）。详见 `docs/指令参考.md`。

| 级 | 指令 | 行为 |
|---|---|---|
| Project | `/newproject <名称> [\| 描述] [@起 ~止]` | 新建项目（起始日期默认今天，并设为默认项目） |
| Project | `/setproject <项目ID>` | 设置长期默认项目 |
| Project | `/getproject` | 查看当前默认项目 |
| Project | `/listproject [n\|all]` | 列出可建实验的项目（`all` = 全部可读） |
| Experiment | `/newexp [标题] [@起 ~止]` | 新建实验草稿（未设默认项目时先引导选项目） |
| Experiment | `/setexp <实验ID>` | 设置当前实验（并把它的所属项目设为默认项目） |
| Experiment | `/getexp` | 查看当前实验 |
| Experiment | `#<实验ID> 文本` | 本条消息直接挂到对应实验 |
| Experiment | `/listexp [n]` | 列出最近 n 个自己的实验（默认 5） |
| Experiment | `/search <关键词>` | 搜索标题/正文含关键词的实验 |
| Task | `/newtask <实验ID> [任务名] [~截止]` | 在指定实验下新建任务 |
| Task | `/listtask <实验ID> [n]` | 列出指定实验下的任务 |
| 跨层 | `/bind <码>` | 绑定 SciNote 账号（未绑定用户主路径，优先于身份解析） |
| 跨层 | `/confirm` | 草稿级软锁：停止追加，待 /newexp 开新草稿或 /done 收尾 |
| 跨层 | `/done` | 收尾：状态置为「已完成」（写真实 done_at）并清草稿索引 |
| 跨层 | `/cancel` | 放弃追加（保留草稿） |
| 跨层 | `/admin [关键词]` | 管理员跨用户查询实验（F9，需实例管理员；按 team 范围） |
| 跨层 | `/book <设备ID> <开始ISO> <结束ISO>` | 设备预约（F10，建 `CalendarEvent`，如 `/book 12 2026-09-24T14:00 2026-09-24T16:00`） |
| 跨层 | `/help` | 输出全部指令用法 |

**群 @ 指派（F6）**：企微群消息中的 `ChatId` + `\u0001@userid\u0001` 提及会被解析为 `chat_id` / `mentions`。被 @ 的微信用户若已绑定，会自动指派为当前草稿实验成员（需发送者有 `manage_users` 权限）；未绑定则回提示。该标记格式以企微会话存档协议为准（真机核实）。

## 架构分层

```
[企微群]  ── wecom_controller → WecomCrypto(验签+解密) → WecomMessageParser ─┐
[ilink私聊]── ilink_controller → IlinkCrypto/Parser ────────────────────────┤
                                                                             ▼
                                      Inbound.receive → BindingResolver(wechat_user_bindings)
                                                                             │ 已绑定
                                                                             ▼
                                              intake（F4/F5，草稿+确认）──→ scinote_service_writer
                                              （CreateExperimentService.new(user, team, params).call 内部置 created_by）
```

- `Message`：双通道归一结构（`user_id, text, media[], type, platform`）。
- `Inbound`：统一入口，`receive` 解密+解析+身份解析，已绑定则交 `intake_handler`（**已由 `engine.rb` 注入为 `Intake.handle`**，进程内写入）。
- 身份解析返回 `scinote_user_id` 或 `nil`（未绑定返回引导文案）。

## 实现进度

- ✅ 引擎 / 配置 / 路由自注册
- ✅ 统一 Message 结构
- ✅ 企微桥接（验签 + AES-256-CBC 解密 + 解析）
- ✅ iLink 桥接（解密 + 解析）
- ✅ 绑定层（解析 / 码 / 指令 / 存储 / 模型 / 迁移）
- ✅ 写入层 intake（F4/F5）：`intake.rb` + `session_draft_store.rb` + `scinote_service_writer.rb`，指令路由 + 草稿 + 写入真实 SciNote
- ✅ 回调控制器已接 `Inbound.receive` 触发写入（回包投递见 Ticket 07）
- ✅ `/bind` 指令已在 `Inbound.receive` 优先拦截（未绑定用户可经私聊绑定；`/confirm` 草稿软锁已实现）
- ✅ 企微群 `ChatId` + @ 提及解析；@ 已绑定用户自动指派到当前实验（F6，权限校验走 `can_manage_experiment_users?`）
- ✅ 管理员跨用户查询（F9，`InstanceAdmin.admin?` + 直查模型）；设备预约（F10，`CalendarEvent` `equipment_booking`）
- ✅ 视觉识别（vision，Ticket 05）：`Vision` sidecar seam + `Media` 下载 seam；图片识别文本写入正文，失败降级仅附件
- ✅ AI 结构化抽取（F12，Ticket 06）：`AiProcessor` LLM seam + `FormulationWriter` 落 `ai_eln` `Formulation`；GLP 原文保留 + 标需人工审核；抽取失败降级原文落库
- ❌ 语音 asr（推后，Ticket 07）
- ⚠️ 媒体**真实附件落库**未实现：`Experiment` 正文不支持内嵌图片（`TinyMceImages` 未含 Experiment），v1 `upload` 仅正文占位；真实挂接需建任务 `Result`/`Asset`（Ticket 08 真机核实）

## 移植清单（Python → Ruby，来自 wechat_to_elabftw）

| Python（参考） | Ruby 目标 | 状态 |
|---|---|---|
| `intake.py::Intake` + `DraftStore` | `lib/.../intake.rb` + `session_draft_store.rb`（生产换 Redis/DB） | ✅ |
| `intake._new/_use/_append/_done/_cancel/_list/_search` 指令路由 | `intake.rb` 同签名方法 | ✅ |
| `backend.ElabBackendAdapter` | `scinote_service_writer.rb`（`CreateExperimentService` 等，置 `created_by`） | ✅ |
| `naming.enforce_attach/enforce_title` | 标题用 `enforce_title`（草稿头 `header`）；附件命名规范 v1 未强制（Ticket 05） | ⚠️ |
| `asr.py` / `vision.py` | Ruby 移植 / Python sidecar | ❌ 推后 |
| `ai_processor.py` | Ruby LLM 抽取 → Formulation 实体 | ❌ 增强 |
| `app.py::webhook` | 已由 `wecom_controller` / `ilink_controller` 覆盖 | ✅ |

> v1 已知简化（需 Ticket 07/08 真机核实）：① `/done` 锁定以「🔒 完成于 `<iso8601>`」正文行表达（SciNote 实验无独立 status 字段）；② 媒体**真实附件落库**未做 —— `Experiment` 正文不支持内嵌图片（`TinyMceImages` 未含 Experiment），`upload` 仅正文占位；图片识别文本已可用，真实挂接需建任务 `Result`/`Asset`（Ticket 08 核实）；③ 草稿 store 为进程内 Hash，多 worker 需换 Redis/DB。详见 `docs/development/wechat-gateway-plan.md`。

## 测试

- 框架：**rspec**（遵循 `addon-dev-workflow.md` 约定，`config/initializers/load_addons_specs.rb` 在 test/dev boot 把 `addons/wechat_gateway/spec` 自动 symlink 到 `spec/addons/wechat_gateway`）。
- 已有 spec：`spec/lib/scinote/wechat_gateway/` 下
  - 解析层（纯 Ruby，可无实例单测）：`configuration_spec` / `binding_resolver_spec` / `wecom_crypto_spec` / `ilink_bridge_spec` / `inbound_spec`
  - 写入层：`intake_spec`（用内存 `FakeBackend` 复刻后端接口，**无真实 DB 依赖**）、`session_draft_store_spec`、`scinote_service_writer_spec`（`instance_double` stub 宿主 `CreateExperimentService`/`Project`/`Experiment`/`User`，验证映射与审计链）
- Windows 宿主不支持 symlink 时 fallback：`rspec addons/wechat_gateway/spec`。
- 运行：`bundle exec rspec spec/addons/wechat_gateway`（或 `addons/wechat_gateway/spec`）。
