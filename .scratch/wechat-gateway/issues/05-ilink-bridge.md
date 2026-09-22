# 05 — iLink 私聊 DM 桥接

**What to build:** `ilink_bridge` 长轮询 iLink `get_updates` 收私聊 DM，转 `Inbound.dispatch(:ilink, ...)`。AES-128-ECB 解密按 iLink SDK 思路（Ruby 实现）。

**Blocked by:** 01

**Status:** resolved

- [x] iLink 媒体 `AES-128-ECB` 解密（`IlinkCrypto`，纯 Ruby，可 roundtrip 单测）
- [x] DM 消息解析 → 统一 `Message`（`IlinkMessageParser`，按 `*_item` 子结构识别，不依赖 SDK 枚举值）
- [x] 长轮询循环 + `BOT(2)` 自回包跳过 + 交 `Inbound`（`IlinkBridge`，transport 可注入）
- [x] `Message` 统一结构 + `Inbound.dispatch(:ilink, msg)` 解析真实用户（单测：未绑定返回 nil）
- [x] 单测 9 runs / 19 assertions / 0 failures（`ruby test/ilink_test.rb`）

## Answer
- 新增文件（均纯 Ruby、可脱离 Rails 单测）：
  - `lib/scinote/wechat_gateway/message.rb` — 统一 `Message(user_id, text, media[], type, platform, raw, timestamp)`
  - `lib/scinote/wechat_gateway/ilink_crypto.rb` — `decode_aes_key`(base64→16字节) / `aes128_ecb_decrypt` / `decrypt_media`
  - `lib/scinote/wechat_gateway/ilink_message_parser.rb` — `parse(raw)` 归一到 `Message`（文本/图片/语音/文件/视频；`ILINK_GROUP_FIELD` 群模式改 `user_id` 为 `g.<room>.<sender>`）
  - `lib/scinote/wechat_gateway/ilink_bridge.rb` — `process`/`run`(长轮询, 注入 poller) / `download_media`(注入 http_get)
  - 改造 `inbound.rb`：`dispatch(platform, message)` 用 `BindingResolver` 解析真实 `scinote_user_id`（或 nil）
  - 入口 `lib/scinote/wechat_gateway.rb` 补充 require

## Comments
- **关键假设（需真机/SDK 核对）**：第三方 `wechatbot` SDK 未 vendored 到本仓库，`decode_aes_key` 按「16 字节密钥的 base64」实现（即 `Base64.decode64(aeskey)`），未做额外 md5。若真实 iLink 下发为 md5 派生，需改 `decode_aes_key`。
- **真实长轮询 transport 未实现**：`get_updates` 端点/参数/login(QR 扫码)/`sync_key` 推进属 iLink 私有协议（在 SDK 内），本仓库未含。现有 `IlinkBridge.run(poller)` 只实现「拿到 raw → 解析 → 分发」确定逻辑，真实 transport 待实例联调补上（协议细节见 Python `ilink_bridge.py` 所依赖的 `wechatbot` SDK）。
- 媒体下载默认走 `Net::HTTP`；真实 `full_url`（含 taskid）优先于 `encrypted_query_param` 拼接，沿用 Python 版经验。
- 端到端联调需实例 boot + 真机 iLink 凭据（环境受限）。
