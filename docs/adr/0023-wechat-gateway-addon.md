# 0023 — 微信/企微录入网关 Addon（进程内 Rails Engine，双通道统一写入层）

> 来源：`F:\eln开发\wechat_to_elabftw\docs\WECHAT-SCINOTE-PLAN.md`（2026-09-10 架构决策）；
> 参考实现：`F:\eln开发\wechat_to_elabftw`（Python 版 eLabFTW 网关，仅作逻辑参考，不并入 addon）。
> 落地：`addons/wechat_gateway`（命名空间 `Scinote::WechatGateway`）。

## Status

Accepted（架构决策 2026-09-10）。实现进行中：绑定层 + 双通道桥接层 + 写入层（intake）已完成，剩余增强（AI / 媒体真实附件 / `/bind` 链路 / 群@指派）待落地（见「实现进度」）。

## Context

要把微信群 / 企微群 / 私聊里的实验记录自动落到 SciNote，并支持「组长派任务给组员」。最初方案是独立 Python 网关 + Doorkeeper OAuth2，但经源码核实：

- SciNote 认证为 Doorkeeper（`grant_flows %w(authorization_code)`，无 password / client_credentials），`experiments_controller#create` 强制 `created_by: current_user`。
- 独立网关要「以某人名义建记录」就必须持有每人 token，且企微群事件 / 管理员查询 / 设备预约等在 v1 API 子集下有缺口。

iLink bot 实测（2026-08-24）：平台不向 bot 投递普通微信群事件，群聊 @ + 多人 + 派任务必须走**企业微信自建应用**。

## Decision

1. **改为进程内 Rails Engine addon**（不再独立 Python 网关）。同进程直调 SciNote service / 模型，免逐用户 OAuth token；映射只存 `wechat_id → scinote_user_id`，不存 JWT。
2. **双通道统一收敛**：iLink（私聊 DM）+ 企业微信（群聊 + @ + 派任务），两条入口在 addon 内统一产出 `Message(user_id, text, media[], type)`，下游写入逻辑完全共用。
3. **身份绑定用「一次性绑定码」而非 OAuth**：用户在 SciNote 设置页生成绑定码（绑到生成时 `current_user`），微信发 `/bind <码>` 完成；全程不碰 Doorkeeper。
4. **写库作者用真实用户身份**：addon 调 `Experiments::CreateService.call(user: <真实用户>, ...)`，service 置 `created_by`，保证 GLP 审计链正确（草稿 + `/confirm` 两阶段：先建草稿，本人确认才锁定）。
5. **零入侵注册**：宿主 `Gemfile` 一行 `gem 'scinote_wechat_gateway', path: 'addons/wechat_gateway'`，路由由 `engine.rb` initializer 自挂载到 `/wechat_gateway`（遵循 0022 统一机制）。

## 实现进度（addons/wechat_gateway 现状）

| 模块 | 文件 | 状态 |
|---|---|---|
| 引擎 / 路由自注册 / ENV 配置 | `lib/scinote/wechat_gateway/engine.rb`, `configuration.rb` | ✅ 完成 |
| 统一消息结构 | `message.rb` | ✅ 完成 |
| 企微桥接：验签 + AES-256-CBC 解密 + 解析 | `wecom_crypto.rb`, `wecom_message_parser.rb` | ✅ 完成 |
| iLink 桥接：解密 + 解析 | `ilink_bridge.rb`, `ilink_crypto.rb`, `ilink_message_parser.rb` | ✅ 完成 |
| 绑定层：解析 / 码生成 / 指令 / 存储 / 模型 / 迁移 | `binding_resolver.rb`, `bind_code.rb`, `bind_command.rb`, `active_record_binding_store.rb`, `app/models/.../wechat_user_binding.rb`, `db/migrate/20260910120000_*` | ✅ 完成 |
| 回调控制器 | `app/controllers/.../wecom_controller.rb`, `ilink_controller.rb`, `bind_controller.rb` | ✅ 已接 `Inbound.receive` 触发写入（回包投递见 Ticket 07）；`/bind` 已在 `Inbound.receive` 优先拦截，`/confirm` 草稿软锁已实现 |
| 统一入口 / 身份解析 | `inbound.rb` | ✅ `intake_handler` 已由 `engine.rb` 注入为 `Intake.handle`（进程内写入） |
| **写入层 intake（F4/F5）** | `intake.rb` / `session_draft_store.rb` / `scinote_service_writer.rb` | ✅ 完成（指令路由 + 草稿 + 落真实 SciNote；v1 锁定以正文时间戳行表达，媒体仅占位） |
| 群 @ 解析 + 指派（F6） | `wecom_message_parser.rb`（`chat_id`/`mentions`）、`scinote_service_writer.rb#assign_user`（`can_manage_experiment_users?` + 多态 `UserAssignment`） | ⚠️ 群 @ 解析完成；**指派语义有误**——现写实验级 `user_assignments`（角色指派），任务卡片看不到负责人。F6 应为任务指定成员 `UserMyModule`，见 **0024**（实现待拍板） |
| 管理员查询（F9）/ 设备预约（F10） | `scinote_service_writer.rb#admin_experiments`（`InstanceAdmin.admin?` 直查）、`#book_equipment`（`CalendarEvent` `equipment_booking`） | ✅ 完成（SciNote 无 `EquipmentBooking` 模型，实为 `CalendarEvent`） |
| AI 结构化抽取（F12，Ticket 06） | `ai_processor.rb`, `formulation_writer.rb` | ✅ 完成（LLM JSON 抽取 + 落 ai_eln `Formulation`；GLP 原文保留；失败降级原文） |
| 视觉识别（vision，Ticket 05） | `vision.rb`, `media.rb` | ✅ 完成（sidecar HTTP 识别 → 正文；失败降级仅附件） |
| 语音 / asr + 媒体真实附件 | 缺 | ❌ 推后（asr 见 Ticket 07；真实附件需任务 `Result`/`Asset`，Ticket 08 核实） |

## Consequences / 风险

- 与 SciNote 内部耦合更紧：升级 SciNote 时 service / model 签名变化需同步 addon（decorator 谨慎）。
- 企微 webhook 须公网 HTTPS（已挂 SciNote 域 `/wechat_gateway/wecom/callback`，复用既有 TLS，无独立反代）。
- 群聊强依赖企微；iLink 仅私聊。
- 指派 create 语义、草稿 `/confirm` 状态语义、绑定码 UI（deface 面板）需真实实例实测（plan §5/§7/§14）。
- 本地起实例受阻（C 盘满 / Docker 未装）时，建议先用 mock service 联调。

## 关联

- 0022（addon 路由自注册）
- 0020（addon 配置自声明 / 设置页 addon 化）
- 0005（addon 注册约定）
- `WECHAT-SCINOTE-PLAN.md`（完整需求 + 分阶段计划 + 企微技术要点）
- `addons/wechat_gateway/README.md`（运维 / 指令 / 环境变量）
