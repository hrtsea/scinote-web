# 03 — 统一消息入口 Inbound

**What to build:** `Inbound.dispatch(platform, raw)` 把 wecom / ilink 消息归一为 `Message(user_id, text, media[], type)`，调 `BindingResolver` 得 `scinote_user`，再交 `intake`。

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] 统一 `Message` 结构
- [ ] 解析企微 XML / iLink payload → `Message`
- [ ] 接 `BindingResolver` → `scinote_user`（未绑定返回引导）
- [ ] 交 `intake`（06 落地后接通）
