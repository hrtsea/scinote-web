# 04 — 企微回调验签与 AES-256-CBC 解密

**What to build:** `WecomCrypto` 实现企微回调 GET 校验（`msg_signature = sha1(sort([token, timestamp, nonce, encrypt]).join)`）与 POST 消息 AES-256-CBC 解密（`EncodingAESKey` → 32 字节 key，`IV = key[0,16]`，PKCS7 `block_size = 32`；明文 = `rand16 + len(N) + msg + receiveid`）。详见 plan §9.2。

**Blocked by:** 01

**Status:** resolved

- [x] `encrypt` / `decrypt` 纯方法（base64 + OpenSSL）
- [x] `verify_signature`（SHA1 sort）
- [x] `verify_url` / `decrypt_callback` Rails 封装（读 config）
- [x] 加解密 roundtrip 单测通过（`ruby test/wecom_crypto_test.rb`）
- [ ] 真实企微回调联调（需 corpid / EncodingAESKey）

## Answer
实现于 `addons/wechat_gateway/lib/scinote/wechat_gateway/wecom_crypto.rb`，纯 Ruby（不依赖 Rails）。关键点：
- `EncodingAESKey`(43字符) + `'='` → Base64 解码得 32 字节 key；`IV = key[0,16]`；`AES-256-CBC`。
- PKCS7 **block_size = 32**（微信实现用 32，非 AES 块 16）；明文 = `rand16 + len(N,大端) + msg + receive_id`。
- 修复：`encrypt` 拼接须全程 BINARY（`msg`/`receive_id` 经 `.encode('UTF-8').bytes.pack('C*')`），否则与 `random_bytes` 混排抛 `Encoding::CompatibilityError`。
- 单测 `test/wecom_crypto_test.rb`（minitest，脱离 Rails 可跑）：roundtrip 含中文/emoji、签名有效/篡改、receive_id 校验、XML 回调解密，4 runs / 0 failures。

## Comments
- 验证命令：`Set-Location addons/wechat_gateway; ruby test/wecom_crypto_test.rb`（Ruby 3.4）。
- 真实联调仍待企微 corpid / EncodingAESKey（环境 C 盘满 + Docker 未装，暂无法 boot SciNote）。

### Gem 评估结论（2026-09-10）：`Eric-Guo/wechat` 不能用于回调加解密
- 已 `gem install wechat -v 1.2.0`（装到 `F:\ruby_gems` 自定义 GEM_HOME，避开 C 盘）。
- 实证：`Wechat::Cipher` 的 IV 计算为 `cipher.iv = [key_data].pack('H*')`（其中 `key_data = Base64.decode64(EncodingAESKey+'=')`，二进制 32 字节）。`pack('H*')` 对二进制产出与微信规范 `IV = key[0,16]` **不同的** 16 字节。
- 后果：gem 自身加解密自洽，但**无法解密真实企微回调**（用标准 `key[0,16]` 加密的密文，gem `decrypt` 抛 `OpenSSL::Cipher::CipherError: wrong final block length`）。`Wechat::Responder`（回调控制器 DSL）同样 `include Cipher`，故整条回调链都不兼容。
- 决定：**保留自研 `WecomCrypto`**（规范 `key[0,16]`，正确）。gem 仅用于出站 `Wechat::CorpApi`（`message_send` / `get_material` / `getuserinfo` / `getuserid`），该路径走 HTTPS+access_token，不涉及回调 AES，不受此 IV bug 影响。gemspec 已加 `s.add_dependency 'wechat'`。
