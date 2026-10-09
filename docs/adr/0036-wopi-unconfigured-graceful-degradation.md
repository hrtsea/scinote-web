# ADR-0036: WOPI 未配置时资产 view/edit 优雅降级

## Status
**Accepted**

> 已实现并通过**生产 HTTP 真浏览器验证**（2026-10-08）。降级策略：WOPI 不可用时
> `AssetsController#view/#edit` 提前返回、渲染 `assets/unsupported` 降级页
> （**HTTP 200**，含指向 active_storage blob 的下载链接），不再 500。
> 验证证据见文末「实施与验证」。

## Context

在 `scinote_web_production` 容器（WOPI 未配置：`WOPI_DISCOVERY_URL` 为空、`WOPI_ENABLED` 非 `'true'`）上，
对**任意** asset 访问 `/files/:id/view` 与 `/files/:id/edit` 均触发 `HTTP 500`。

### 崩溃链（已用临时补丁逐层确认）
1. `app/controllers/assets_controller.rb:197-199`（`edit`）与 `:211-212`（`view`）**无条件**调用
   `@action_url = append_wd_params(@asset.get_action_url(current_user, action, false))`，
   没有 `if @asset.can_perform_action(...)` 之类的门控。
2. `Asset#get_action_url`（`app/models/asset.rb:310`）
   → `file_ext = file_name.split('.').last&.downcase`（`:311`）。若 `file_name` 为 `nil`
   → `nil.split` → **`NoMethodError`**（原始崩溃链的第二层）。
   → 进而 `get_action(file_ext, action)`（`app/utilities/wopi_util.rb:20`）
   → `current_wopi_discovery` → `initialize_discovery`。
3. `WopiUtil#initialize_discovery`（`app/utilities/wopi_util.rb:54-56`）在
   `Rails.cache.fetch(:wopi_discovery) { ... URI(ENV.fetch('WOPI_DISCOVERY_URL', nil)) ... }` 中，
   当 `WOPI_DISCOVERY_URL` 为 `nil` 时调用 `URI(nil)` → **`ArgumentError: bad URI(is not URI?)`**
   （原始崩溃链的第一层 / 最外层异常）。

### 根因
- `Asset#can_perform_action`（`asset.rb:292-308`）已经正确地以 `ENV['WOPI_ENABLED'] == 'true'`
  作为总开关，但 **`get_action_url` 缺少同样的前置守卫**，导致即便 `WOPI_ENABLED=false`，
  controller 仍会触发 WOPI 发现逻辑并崩溃。
- `initialize_discovery` 对"未配置"这一合法状态**没有优雅处理**：它假设 `WOPI_DISCOVERY_URL`
  必然存在，否则直接 `URI(nil)` 抛异常，而非返回空发现集（`nil` 或 `{}`）。
- 崩溃发生在**控制器动作内、ERB 渲染之前**，因此前端（含已 Vue 化的 `#assetsOfficeMount` island）
  根本没有机会挂载——这是为何 Vue 迁移产物正确却被 500 挡住的根本原因。

### 影响范围
- **全部** asset view/edit 页面（不限于某类文件），即用户**完全无法在线查看/编辑任何附件**。
- 独立于且不抵消本轮 11 页 Vue 3 化成果；修复后资产页 Vue island 即可正常挂载。

## Decision

采用**配置感知的优雅降级**策略，使资产 view/edit 的可用性不再与 WOPI 配置强耦合：

1. **`initialize_discovery` 守卫**：当 `WOPI_DISCOVERY_URL.blank?`（或 `WOPI_ENABLED != 'true'`）时，
   直接返回空发现集（`nil` 或 `{}`），不发起 `URI(nil)` 请求；既不抛异常，也不污染 cache。
2. **`get_action_url` 守卫**：方法入口先判 `ENV['WOPI_ENABLED'] == 'true'` 且 `file_name` 存在，
   否则返回 `nil`（与既有的 `action.nil? → return nil` 分支一致）。
3. **controller `view`/`edit` 守卫**：`@action_url = ... if @asset.can_perform_action(action)`，
   当 `@action_url` 为 `nil` / false 时，页面渲染原生（非 WOPI）查看器/下载入口，而非 500。
4. **保持 WOPI 开启路径不变**：配置齐全时行为与现状一致（`can_perform_action` 已正确处理开关）。

> 不引入新 gem、不改动 WOPI 协议交互逻辑，仅补充"未配置 = 不可用但不崩溃"的边界处理。

## Options Considered

| 选项 | 描述 | 收益 | 代价 / 风险 |
|---|---|---|---|
| **A. 优雅降级（采纳）** | 守卫 discovery + get_action_url + controller，未配置即降级 | 修复全量 500；WOPI 开/关两条路径行为清晰；零新增依赖 | 需在 3 处补守卫，回归需覆盖"开/关"两种 env |
| B. 强制要求 WOPI 必配 | 在启动/部署时校验 `WOPI_DISCOVERY_URL` 必填，否则 fail-fast | 配置错误尽早暴露 | 本环境（及多数离线部署）本就不配 WOPI，等于让资产页永久不可用——不现实 |
| C. 在 controller rescue 包 500→降级 | `rescue StandardError` 兜底渲染原生查看器 | 改动最小（单点） | 掩盖真实错误、吞掉其他潜在异常；不符合显式门控原则；不利于定位 |

## Consequences

**变得更容易**
- 资产 view/edit 在任意部署（含未配 WOPI 的离线/内网环境）均可用，不再 500。
- 前端 Vue 化资产页（ERB 已含 `#assetsOfficeMount` + `javascript_include_tag 'vue_assets_office'`）能真正运行时挂载。
- WOPI 开关语义收敛到单一真源（`can_perform_action` / `WOPI_ENABLED`），消除"开关关了但代码仍走 WOPI"的隐性不一致。

**变得更难 / 需注意**
- 需补"WOPI 未配置"的回归用例（minitest/request spec），否则降级分支会像今天一样长期无人验证。
- `get_action_url` 返回 `nil` 的语义需在 view 层被正确处理（目前 `append_wd_params(nil)` 也需确认不抛）。

## 修复草图（实施清单）

> 实际实施（2026-10-08）对草图做了两处精炼，见下「实施与验证」：

- [x] `app/utilities/wopi_util.rb#initialize_discovery`：方法开头加
      `return nil if ENV.fetch('WOPI_DISCOVERY_URL', nil).blank? || ENV['WOPI_ENABLED'] != 'true'`
      （未配置即返回空发现集，不再 `URI(nil)` 崩溃）。
- [x] `app/utilities/wopi_util.rb#get_action`：加 `return nil if discovery.blank?`
      （发现集为空时直接不可用，避免 rescue 后拿到非 hash 再崩于 `discovery[:actions]`）。
- [x] `app/models/asset.rb#get_action_url`：入口加
      `return nil unless ENV['WOPI_ENABLED'] == 'true' && file_name.present?`（纵深防御）。
- [x] `app/controllers/assets_controller.rb#view/#edit`：以 `@asset.can_perform_action(action)`
      为门控，不可用时 `return render_asset_unsupported(action)`（新增 private 方法，渲染
      `app/views/assets/unsupported.erb`，`layout: false`）。
- [x] 新增 `app/views/assets/unsupported.erb`：降级页（标题 + "在线查看/编辑未启用"说明 + 下载链接，
      链接用 `rails_blob_path(@asset.file, disposition: 'attachment')`）。
- [ ] 补 request spec（**推迟至 CI**）：未配 WOPI env 下 `GET /files/:id/view` 返回 200 且渲染降级页。
      理由：本项目验收纪律以"生产 HTTP + 真会话"为权威闸门（单测绿 ≠ 生产可点读），本轮已用真浏览器
      登录 hpxing 验证通过，故 request spec 作为回归护栏留待 CI，不在此手写未运行的测试。

## 实施与验证（2026-10-08）

### 对草图的精炼
1. controller 未采用"条件赋值 `@action_url`"的写法，而是**提前 `return render_asset_unsupported`**。
   原因：`edit`/`view` 动作里除 `@action_url` 外还有 `get_wopi_token`、`create_wopi_file_activity`
   等 WOPI 专属调用，仅守卫 `@action_url` 不够——WOPI 关闭时这些调用同样会崩。门控后整段 WOPI
   逻辑被绕过，彻底消除 500。
2. 降级采用**渲染降级页（同 URL 返回 200）**而非 `redirect_to`（302）。原因：ADR 验收标准写的是
   "返回 200 且渲染原生查看器"；同 URL 返回 200 也便于后续回归断言。

### 验证证据（生产 HTTP + 真浏览器，Edge + playwright-core）
- 登录 hpxing（临时改密→验证→从 `/tmp/eln_backup_rt/hpxing_encrypted_password.txt` 还原，已 MATCH）。
- `GET /files/1/view` → **HTTP 200**，未跳登录；页面含"下载文件"文案；下载链接指向
  `/rails/active_storage/blobs/redirect/...?disposition=attachment`；**0 console error**。
- `GET /files/1/edit` → **HTTP 200**，同上。
- 修复前这两个 URL 在本环境 100% 返回 **HTTP 500**（WOPI 未配置崩溃），现已消除。
- 验证脚本：`F:/elnapply_tmp/assets_verify2.js`；容器为 `scinote_web_production`，改 4 个文件后
  `docker restart` 生效。

## 关联
- 运行时验证证据：`F:/elnapply_tmp/vue3_runtime_verification_report.html`（2 页 500 根因段）
- 日常记录：`F:/eln开发/.workbuddy/memory/2026-10-08.md`
- 既有守卫参考：`app/models/asset.rb#can_perform_action`（:292，已正确使用 `WOPI_ENABLED`）
