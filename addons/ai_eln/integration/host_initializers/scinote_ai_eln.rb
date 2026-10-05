# frozen_string_literal: true
#
# ⚠️ 已废弃（2026-09-29）：本片段不再使用，请勿复制到宿主。
#
# 原因：本片段含三处会致 boot / 运行期失败的错误，且宿主接入已按
# `docs/development/addons-host-contract.md` 契约直接落地：
#
#   1. 路由：宿主 `config/routes.rb` 保持**零 mount**——路由由引擎
#      `lib/scinote/ai_eln/engine.rb` 的 `'scinote_ai_eln.routes'` initializer 自挂载。
#      （同目录 `host_routes.rb` 的 `mount` 片段同属作废，勿复制。）
#
#   2. 权限：`Canaid.register_permissions_under(:ai)` 在 Canaid 1.0.4 中**并不存在**
#      （已核实：全仓仅本片段出现该方法）；且 ai_eln 未引入新权限谓词，
#      按契约 §5.1.3 **不需要** `app/permissions` 目录。
#
#   3. 谓词名错误：`user.can_read_protocol?` 与 `user.can_create_experiment?` 均**不存在**。
#      宿主真实谓词（见 `app/permissions/`）：
#        - `user.can_read_experiment?`              ← experiment.rb:21
#        - `user.can_read_protocol_in_repository?`  ← protocol.rb:15
#        - `user.can_read_protocol_in_module?`      ← protocol.rb:103
#        - `user.can_read_asset?`                   ← asset.rb:4
#
# 现行的宿主配置见：`config/initializers/scinote_ai_eln.rb`
