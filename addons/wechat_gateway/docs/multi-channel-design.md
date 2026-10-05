# 多通道 IM 网关综合设计方案（WeChat → 钉钉 / QQ / 飞书 …）

> 目标：把 `wechat_gateway` 从「微信专属」扩展为「任意 IM 渠道统一写入 SciNote」的网关，
> 不绑定单一平台。本文对照各平台官方机制与业界成熟架构，给出现场可落地的方案。
>
> 一手来源见文末「参考来源」。

---

## 1. 结论（先说重点）

- **现有 addon 已经是「半多通道」架构**，核心数据结构无需重构，只需补齐三块：
  1. **Channel 注册表 + 入站适配器（Adapter）**：每个平台一个 `inbound`（验签/解密/解析 → 统一 `Message`）。
  2. **出站发送器（Sender / Outbound）**：当前 `wecom_controller` 只 `Rails.logger.info` 回包，**没有真正把回复发回用户**。钉钉/飞书/QQ 都要求主动调用平台 API 回消息，这是多通道最大的缺口。
  3. **命名与文案泛化**：`wechat_gateway` 命名、`BIND_GUIDANCE`「微信绑定」、`intake.header`「来源：微信群」等需改为与平台无关。
- **业界公认模式是 Channel Adapter（适配器）**：腾讯 WeKnora、百度架构文均采用「每平台独立监听 → 归一为统一 Message → 业务层 → 反向适配器回推」的 producer/consumer 分层。这与本 addon 已有的 `platform` 抽象完全吻合，无需另起炉灶。

---

## 2. 现有架构已具备的多通道能力（不要重复造）

| 能力 | 现状 | 是否需改 |
|---|---|---|
| 绑定关系 | `wechat_user_bindings` 表**已有 `platform` 列** | 无需改结构，新增枚举值即可（`:dingtalk`/`:feishu`/`:qq`…） |
| 统一消息 | `Message` 结构体**带 `platform` 字段** | 无需改 |
| 入站入口 | `Inbound.receive(platform, raw, params)` **已按 platform 分支** | 改为查注册表即可 |
| 身份解析 | `BindingResolver.resolve(user_id, platform)` 已带 platform | 无需改 |
| 写入层 | `Intake` 只认 `user_id` + `Message`，与平台无关 | 仅文案需参数化 |
| 路由自注册 | `engine.rb` 按 `enabled?` 挂载 `/wechat_gateway` | 改为按平台动态挂路由 |

**关键判断**：真正的平台耦合点只有 4 处——`crypto/parser`、`controller/route`、`config`、以及**缺失的 sender**。其余都是平台无关的。

---

## 3. 各平台官方机制对比（设计 Adapter 的依据）

| 平台 | 接收方式 | 验签 / 解密 | 主动回发（出站） | 是否需要公网回调 | 长连接选项 |
|---|---|---|---|---|---|
| **企业微信** | HTTP 回调（加密 XML） | AES-256-CBC + SHA1 签名（`msg_signature`/`timestamp`/`nonce`） | 被动回复（同步 XML，5s 内）或 客服消息 API | 是 | 无（仅回调） |
| **iLink** | 长轮询拉取（pull） | AES-128-ECB 媒体解密 + 业务解密 | 主动 API 推送 | 否（内网） | 长轮询（已有 `IlinkBridge`） |
| **钉钉** | HTTP 回调 **或** Stream（WebSocket） | 与企微**几乎同构**：AES + `token`/`ENCODING_AES_KEY` + `signature`（官方 `DingTalkEncryptor(token,aesKey,ownerKey)`） | Webhook 群机器人 **或** OpenAPI 发送（需 conversation 上下文） | 是（HTTP 回调时）；Stream 不需要 | **Stream 模式**（推荐，免公网） |
| **飞书 / Lark** | HTTP 回调 **或** 长连接（WebSocket） | `X-Lark-Signature` = HMAC-SHA256(`timestamp`+`nonce`+`body`, secret)；首次 `url_verification` 挑战应答 | `im/v1/messages` 主动发送（按 `receive_id_type`=chat_id/user_id/open_id 等） | 是（HTTP 回调时）；长连接不需要 | **长连接**（推荐，免公网） |
| **QQ 机器人** | Webhook（端口 80/443/8080/8443）**或** WebSocket | 请求头 `X-Bot-AppId`/`X-Bot-Token`/`X-Bot-Signature` 验签 | 主动发送 API（`/v2/users/@me/messages` 等，带 `msg_type`+`content`） | 是（Webhook 时）；WS 不需要 | **WebSocket**（官方推荐开发方式） |

**设计要点**：
- 钉钉 inbound 可**直接复用**企微的 AES+签名解密骨架（仅 `ownerKey` 语义从 `corpid` 换成 `corpId/appKey`），实现成本最低。
- 飞书 / QQ / 钉钉(Stream) / iLink 都支持**长连接**，可绕开「公网回调 + 域名校验」的部署痛点——现场若无固定公网 IP，优先用长连接模式。
- **出站是统一必做项**：除企微被动回复外，所有平台都需持 `access_token`（飞书/钉钉/QQ 均用 app_id+secret 换 token）调用发送 API。建议抽象 `Sender#send(platform, to, text)`。

---

## 4. 推荐架构（Channel Adapter + 出站 Sender）

```
[企微群]  ── wecom_controller   → WecomCrypto + WecomParser ─┐
[钉钉]    ── dingtalk_controller → DingtalkCrypto + Parser ──┤
[飞书]    ── feishu_controller   → FeishuVerifier + Parser ──┤  入站适配器（每平台一对）
[QQ]      ── qq_controller       → QqVerifier + Parser    ──┤
[iLink]   ── ilink_bridge(长轮询) → IlinkParser            ──┘
                                                                 ▼
                                          ChannelRegistry[platform] → Inbound.receive
                                                 │  解析+身份解析（平台无关，已有）
                                                 ▼
                                          Intake.handle（指令路由，平台无关，已有）
                                                 │  返回 reply 文本
                                                 ▼
                                          Sender.send(platform, to, reply)  ← 新增出站
```

- **入站**：每个平台一个 `Crypto/Verifier`（验签+解密）+ `Parser`（→ `Message`）。`Inbound.parse` 改为 `ChannelRegistry[platform].parse(raw, params)`，不再 `case` 硬编码。
- **出站（新增）**：`Intake.handle` 现在 `return reply` 文本；控制器拿到 reply 后调用 `Sender.send(platform, user_ref, reply)`。
  - `Sender` 内部按平台取 access_token（带缓存/刷新）、拼装对应消息体（飞书 `im/v1/messages`、钉钉 OpenAPI、QQ `/v2/.../messages`、企微被动 XML 或客服 API）。
  - `Message` 可加 `reply_to` 字段（平台侧的 chat_id / message_id / conversation_id），由 Parser 在解析时填入，供 Sender 定位回发目标。
- **长连接平台**（飞书/钉钉/QQ）：用后台线程/Job 启动 WS/Stream 客户端，收到事件后直接 `Inbound.receive(platform, event, {})`，与 HTTP 控制器共用同一入站链路。

---

## 5. 命名与文案泛化（避免「微信」硬编码）

| 位置 | 现状 | 建议 |
|---|---|---|
| gem / 引擎名 | `scinote_wechat_gateway` / `Scinote::WechatGateway` | **决策点**：是否重命名为 `im_gateway` / `SciNote::ImGateway`（见 §7）。内部可用 alias 过渡。 |
| `BIND_GUIDANCE` | 「请打开 SciNote → 设置 → 微信绑定」 | 改为 `「设置 → IM 绑定」`，平台名由 `platform` 动态拼接 |
| `intake.header` | 「来源：微信群」「微信录入草稿」 | `来源：#{platform_label}` / `#{platform_label}录入草稿`，`platform_label` 来自注册表 |
| `TITLE_PREFIX` | 默认 `微信记录` | 改为 `IM记录` 或按平台取前缀 |
| 路由前缀 | `/wechat_gateway` | 可保留兼容，或改为 `/im_gateway`（注册表驱动挂载 `/:platform/callback`） |

---

## 6. 推荐落地步骤（分阶段，每步可验证）

1. **抽象 `Channel` 注册表**：`ChannelRegistry.register(platform, inbound:, sender:)`，`Inbound.parse` / 路由挂载改为查表。
   - 验证：`Inbound.receive(:wecom, ...)` 与现有行为一致（已有 `inbound_spec` 不破）。
2. **抽出 `Sender` 接口 + 企微被动回复实现**（先把现有「只日志」变成真正回发）。
   - 验证：`wecom_controller` 对绑定用户返回被动 XML 回复。
3. **钉钉 Adapter**：复用加密骨架写 `DingtalkCrypto` + `DingtalkParser` + `DingtalkSender`；先 HTTP 回调，后补 Stream。
   - 验证：单测解密 + 一条端到端 `/bind`→`/newexp`→回发。
4. **飞书 Adapter**（长连接优先）：`FeishuVerifier` + `FeishuParser` + `FeishuSender` + WS 客户端 Job。
5. **QQ Adapter**：`QqVerifier` + `QqParser` + `QqSender` + WS 客户端 Job。
6. **文案 / 命名泛化**：`BIND_GUIDANCE`、`intake.header`、`TITLE_PREFIX` 参数化；视决策重命名引擎。

---

## 7. 决策点 / 取舍（需你拍板）

- **A. 是否重命名引擎？**
  - 选项 1（推荐，符合「一次重构到位」偏好）：重命名为 `SciNote::ImGateway` / `im_gateway`，路由 `/im_gateway`，绑定表可保留 `wechat_user_bindings` 名或改名 `im_user_bindings`（迁移加 `platform` 已存在，改名需新迁移）。
  - 选项 2（最小改动）：保留 gem 名，仅内部泛化；对外仍叫 `wechat_gateway`。
- **B. 收消息方式**：现场有公网 + 域名 → 用 HTTP 回调（部署简单）；无公网 → 飞书/钉钉/QQ 全用长连接（WS/Stream），免回调配置。
- **C. 是否上消息队列**：当前进程内同步处理足够；若多平台并发高，可加 Redis/Kafka 做 producer/consumer 解耦（百度架构文方案），但属于扩展项，不在首版。

---

## 8. 参考来源（一手 / 官方）

- 钉钉「回调事件消息体加解密」：https://developers.dingtalk.com/document/app/callback-event-message-body-encryption-and-decryption
- 钉钉「接收回调消息 / 配置 HTTP 推送」：https://developers.dingtalk.com/document/app/receive-callback-message ；https://open.dingtalk.com/document/orgapp/configure-http-push
- 钉钉「机器人回复/发送消息（Webhook & OpenAPI）」：https://open.dingtalk.github.io/developerpedia/docs/learn/bot/appbot/reply/ ；https://open.dingtalk.com/document/dingstart/robot-reply-and-send-messages
- 钉钉「Stream 模式概述」：https://open-dingtalk.github.io/developerpedia/docs/explore/tutorials/stream/overview/
- 飞书「事件订阅概述」：https://open.feishu.cn/document/server-docs/event-subscription-guide/overview
- 飞书「接收消息事件」：https://open.feishu.cn/document/server-docs/im-v1/message/events/receive
- 飞书「自定义机器人 / 加签验证」：https://open.larksuite.com/document/client-docs/bot-v3/add-custom-bot
- QQ 机器人「Webhook 方式」：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/webhook.html
- QQ 机器人「事件订阅与通知（含签名校验）」：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html
- QQ 机器人「启动接入 / 消息收发」：https://bot.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/
- 企业微信「加解密方案说明」：https://developer.work.weixin.qq.com/document/path/90968
- 企业微信「接收消息概述」：https://developer.work.weixin.qq.com/document/path/90238
- 腾讯 WeKnora（多通道 IM 适配器：WeCom/Feishu/Slack/Telegram/DingTalk/Mattermost）：https://github.com/Tencent/WeKnora
- 多平台聊天机器人架构（producer→归一 Message→queue→consumer→反向适配器）：https://developer.baidu.com/article/detail.html?id=6009725
