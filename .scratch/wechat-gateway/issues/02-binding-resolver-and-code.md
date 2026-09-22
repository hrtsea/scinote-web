# 02 — 绑定解析与绑定码生成（F3/F8）

**What to build:** `BindingResolver` 按 `wechat_id + platform` 查 `scinote_user_id`；未绑定触发引导。绑定码生成（一次性 + 过期 + 绑定生成时 session 用户），`/bind <码>` 确认写 `wechat_user_bindings`。

**Blocked by:** 01

**Status:** resolved

- [x] `BindingResolver.find_or_nil(wechat_id, platform)`（`resolve` / `bound?`）
- [x] `BindCode` 生成 / 校验 / 过期（一次性 + 过期，绑定生成时用户）
- [x] `/bind <码>` 确认：写 `wechat_user_binding` + 回执（`BindCommand`）
- [x] 单元测试（无 Rails：用 fake binding store）—— 6 runs / 17 assertions / 0 failures

## Answer
- 存储后端注入（duck-typed），逻辑与 Rails 解耦，可无实例单测：
  - `lib/scinote/wechat_gateway/binding_resolver.rb` — `resolve` / `bound?`
  - `lib/scinote/wechat_gateway/bind_code.rb` — `generate`（无歧义字母表 `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`，8 位）/ `verify` / `consume`
  - `lib/scinote/wechat_gateway/bind_command.rb` — `/bind <码>` 解析→校验（已绑定/失效）→`create_binding`→回执
  - `app/models/scinote/wechat_gateway/active_record_binding_store.rb` — 真实后端：绑定落 `wechat_user_bindings` 表，绑定码放 `Rails.cache`（免新迁移）
- 顺带修复 ticket 01 的隐患：补 `lib/scinote/wechat_gateway.rb` 入口（gemspec 默认 `require 'scinote_wechat_gateway'`，原缺该文件→引擎不会加载）。现入口统一 require version/engine/各模块。

## Comments
- 验证：`ruby test/binding_test.rb`（FakeStore 覆盖一次性/过期/已绑定/格式错误）。
- 真实后端（AR + Rails.cache）需实例 boot 验证；绑定码用缓存，故无需新增迁移。
