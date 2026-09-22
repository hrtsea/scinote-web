# 01 — Engine 路由自注册与 enabled 开关

**What to build:** 确认 addon 以进程内 Engine 自注册路由（engine.rb 的 `routes` initializer 把 Engine `mount` 到 `/wechat_gateway`），宿主 `config/routes.rb` 零修改；加 `enabled` 开关与基础 config（wecom token / EncodingAESKey / corpid，ilink token）。禁用时路由不加载。详见 `docs/agents/scinote-addon-autoload-mechanism.md`。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] engine.rb 已自注册 routes（`mount => '/wechat_gateway'`）
- [x] 宿主 `Gemfile` 已加 `gem 'scinote_wechat_gateway', path: 'addons/wechat_gateway'`
- [x] 迁移表 `wechat_user_bindings` 已建（`db/migrate/20260910120000_create_wechat_user_bindings.rb`）
- [x] gem 入口 `lib/scinote/wechat_gateway.rb` 已补（原缺失→引擎不会加载；见 ticket 02 Answer）
- [x] 加 `enabled` 开关（`lib/scinote/wechat_gateway/configuration.rb` + engine.rb 内 `next unless enabled?`）
- [x] engine.rb 内 config initializer 读 wecom/ilink 凭证（ENV）并喂 `WecomCrypto.config`
- [ ] 验证：`Rails.application.routes` 含 `/wechat_gateway/*`，且 `WECHAT_GATEWAY_ENABLED=false` 时不挂载（需实例 boot）

## Answer
- 新增 `lib/scinote/wechat_gateway/configuration.rb`：`Configuration`（enabled / wecom_token / wecom_encoding_aes_key / wecom_corpid / ilink_token / ilink_base_url）+ 模块级 `configuration` / `configure` / `enabled?`。
- `engine.rb`：`scinote_wechat_gateway.config` initializer（声明在 routes 之前）读 ENV 设 enabled 与凭证；`WECHAT_GATEWAY_ENABLED=false` 关；并把企微凭证写入 `WecomCrypto.config`。`scinote_wechat_gateway.routes` initializer 改为 `next unless Scinote::WechatGateway.enabled?` 再 `mount`，disabled 时 `/wechat_gateway/*` 完全不挂载（退化原生 SciNote）。
- 入口文件 `lib/scinote/wechat_gateway.rb` 在 engine 前 require configuration。

## Comments
- 验证：`ruby test/configuration_test.rb` 通过（默认启用 / configure 块设开关与凭证 / 布尔反射）。engine.rb 经 `ruby -c` 语法 OK。
- 挂载 gating 的逻辑已就位，但「disabled 时不挂载」需实例 boot 跑 `Rails.application.routes` 最终确认（环境受限）。
- 排序说明：config initializer 声明早于 routes initializer，故 routes 看到正确开关；宿主若用 `configure` 块覆盖 enabled，建议在引擎加载前（如更早的 initializer）设置，否则挂载已完成。ENV 是挂载开关的权威来源。
