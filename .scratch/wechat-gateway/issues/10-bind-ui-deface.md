# 10 — 绑定码设置页 UI（deface 注入）

**What to build:** 经 decorator + `prepend_view_path` 在 SciNote 设置页注入"微信绑定"面板，显示一次性绑定码与解绑按钮（宿主 `routes.rb` 零修改）。详见 `docs/agents/scinote-addon-autoload-mechanism.md`。

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] `AddonsController#index` decorator 注入变量
- [ ] 绑定码 partial（`prepend_view_path`）
- [ ] 解绑
