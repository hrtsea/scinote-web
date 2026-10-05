# frozen_string_literal: true
#
# ⚠️ 已废弃（2026-09-29）：本片段不再使用，请勿复制到宿主 `config/routes.rb`。
#
# 依据 `docs/development/addons-host-contract.md` §5/§6.1：
#   - 路由由 addon engine **自挂载**（`lib/scinote/ai_eln/engine.rb` 的
#     `'scinote_ai_eln.routes'` initializer，`after: :add_routes` 时
#     `app.routes.append { mount ... }`）。
#   - 宿主 `config/routes.rb` 保持**零 mount**，`routes.rb:14-17` 的注释即为此约定。
#   - 契约 §6.1 明确点出：生成器 README 里的 `mount` 指引是**过时的高危偏差**。
#
# 保持宿主零 mount 的好处：从 Gemfile 注释掉本 addon 时，宿主仍能正常 boot，
# 仅本 addon 端点 404。
