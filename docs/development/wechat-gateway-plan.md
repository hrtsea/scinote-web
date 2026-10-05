# 微信 / 企微网关 Addon 开发计划

> 目标 addon：`addons/wechat_gateway`（`Scinote::WechatGateway`，进程内 Rails Engine）
> 设计依据：`F:\eln开发\wechat_to_elabftw\docs\WECHAT-SCINOTE-PLAN.md`（2026-09-10 决策：addon 化、双通道、绑定码非 OAuth）
> 架构决策：`docs/adr/0023-wechat-gateway-addon.md`
> 参考实现（仅逻辑参考，不并入）：`F:\eln开发\wechat_to_elabftw`
> 开发约定：`docs/development/addon-dev-workflow.md`（铁律：改动只收敛进 `addons/wechat_gateway/`）

---

## 0. 现状盘点（已核实 `addons/wechat_gateway` 代码）

### 已完成
- 引擎 + ENV 配置 + 路由自注册：`lib/scinote/wechat_gateway/engine.rb`、`configuration.rb`
- 统一消息结构：`lib/scinote/wechat_gateway/message.rb`
- 企微桥接：`wecom_crypto.rb`（AES-256-CBC 验签+解密）、`wecom_message_parser.rb`
- iLink 桥接：`ilink_bridge.rb`、`ilink_crypto.rb`、`ilink_message_parser.rb`
- 绑定层：`binding_resolver.rb`、`bind_code.rb`、`bind_command.rb`、`active_record_binding_store.rb`、`app/models/scinote/wechat_gateway/wechat_user_binding.rb`、迁移 `db/migrate/20260910120000_create_wechat_user_bindings.rb`
- 控制器：`wecom_controller.rb`、`ilink_controller.rb`、`bind_controller.rb`
- 测试（minitest）：`test/binding_test.rb`、`configuration_test.rb`、`ilink_test.rb`、`inbound_test.rb`、`wecom_crypto_test.rb`

### 缺口（按 WECHAT-SCINOTE-PLAN 映射）
- ✅ **写入层 intake（F4/F5）**：`intake.rb` / `session_draft_store.rb` / `scinote_service_writer.rb` 已落地（Ticket 01）
- ✅ 控制器已接 `Inbound.receive` 触发写入；`Inbound.intake_handler` 已由 `engine.rb` 注入为 `Intake.handle`
- ✅ `/bind` 指令已在 `Inbound.receive` 优先拦截（`BindCommand` 接入，未绑定用户可私聊绑定）→ Ticket 02 已完成核心
- ⚠️ `/done` 锁定：v1 以正文「🔒 完成于」行表达（SciNote 实验无独立 status 字段，需实例评估 read_only 方案）；`/confirm` 同见 Ticket 02
- ✅ 企微群 `ChatId` + @ 解析；@ 已绑定用户自动指派到当前实验（F6，实验级）→ Ticket 03 已完成核心；任务级指派待 F12
- ❌ 管理员查询（F9）/ 设备预约（F10）
- ❌ 视觉识别（vision，v1 进）/ AI 结构化抽取（F12，增强）/ 语音 asr（推后）

---

## 1. 阶段与 Ticket 拆分

### Ticket 00 — 脚手架收口与契约复核
- [ ] 复核引擎类名以 `Scinote` 开头、`isolate_namespace` 正确（已满足）
- [ ] Gemfile 注册行确认存在（已满足）
- [x] **测试框架决策（已落地）**：已迁到 **rspec**，对齐 `addon-dev-workflow.md` 约定。`test/*.rb`（minitest）全部移植为 `spec/lib/scinote/wechat_gateway/*_spec.rb`，由 `config/initializers/load_addons_specs.rb` 自动 symlink 到 `spec/addons/wechat_gateway`；gemspec `s.test_files` 已指向 `spec/**/*`；旧 `test/` 目录已清空。`
- [ ] 补 `addons/wechat_gateway/README.md` 引用（已完成，见 addon 目录）

### Ticket 01 — 写入层 intake 核心（F4/F5）【最大块】 ✅ 已完成
目标：把 Python `intake.py` 的指令路由 + 草稿追加移植为 Ruby，经 `scinote_service_writer` 落 SciNote。

- [x] 新建 `lib/scinote/wechat_gateway/session_draft_store.rb`
  - 接口：`get(user_id)` / `put(user_id, exp_id, body)` / `pop(user_id)`；进程内 Hash（生产换 Redis/DB）
- [x] 新建 `lib/scinote/wechat_gateway/scinote_service_writer.rb`
  - `create_experiment(title, body)` → `CreateExperimentService.new(user, team, params).call`（**真实签名**，非 plan 假设的 `Experiments::CreateService.call(user:, ...)`；内部置 `created_by=@user` 满足审计链）
  - `append_note(exp_id, block)` → `experiment.update!(description:, last_modified_by: user)`（拼接不覆盖）
  - `get_experiment(exp_id)` → `Experiment.find` 校验存在/权限（抛异常由 Intake 转提示）
  - `list_experiments(q:, limit:)` → 复用 `Experiment.search(user, false, q)`
  - `upload(exp_id, path, caption)` → **v1 仅正文占位**（真实 ActiveStorage 挂接见 Ticket 05）
  - `timestamp(exp_id)` → 追加「🔒 完成于 `<iso8601>`」行（v1 表达锁定；待评估 read_only）
- [x] 新建 `lib/scinote/wechat_gateway/intake.rb`
  - `Intake#handle(user_id, message)` 统一入口；指令 `/new` `/use <id>` `#<id> 文本` `/done` `/cancel` `/list [n]` `/search <q>`（复刻 `intake.py` 行 64–99）
  - 草稿头与 Python `_header` 一致；`media` 处理（图片/语音/文件/视频 → 附件占位 + 备注）
  - `Intake.handle(user_id, message)` 类方法：解析 `User.find` 并构建 writer（用户不存在转友好提示）
- [ ] 新建 `lib/scinote/wechat_gateway/naming.rb`（写库前命名规范）→ 推迟至 Ticket 05（v1 标题用 `enforce_title` 简单拼接，附件命名未强制）
- [x] 接线
  - `engine.rb` 注入 `Inbound.intake_handler = ->(user_id, msg){ Intake.handle(user_id, msg) }`（仅 enabled 时）
  - 控制器改调 `Inbound.receive`（记录回包，真实 outbound 投递见 Ticket 07）
- [x] 测试：`spec/lib/scinote/wechat_gateway/intake_spec.rb` + `session_draft_store_spec.rb` + `scinote_service_writer_spec.rb`
  - `intake_spec` 用内存 `FakeBackend`（忠实复刻后端接口，无真实 DB）；覆盖建实验→追加→`/use`→`#id`→`/done`→`/cancel`→`/list`→`/search`→媒体→降级
  - `scinote_service_writer_spec` 用 `instance_double` stub 宿主 `CreateExperimentService`/`Project`/`Experiment`/`User`，验证映射与审计链

> **实测结论（替代 plan §5 假设）**：`CreateExperimentService.new(user, team, params)` 才是真实入口；`params` 需 `project:`（Project 实例，否则自动建项目）、`name`、`description`；`created_by`/`last_modified_by` 由服务内部置为传入 `user`。实验模型无独立 `status` 字段，故 `/done` 锁定以正文时间戳行表达。

### Ticket 02 — 草稿 /confirm 锁定 + 绑定码接线（F8 落地） ✅ 核心已落地
- [x] `Inbound.receive` 先判 `/bind <码>` → 调 `BindCommand#call`（在身份解析前拦截，未绑定用户主路径；`inbound_bind_spec` 覆盖有效/已绑定/无效码/非绑定分支）
- [x] `/confirm` 草稿级软锁：`SessionDraftStore` 增 `locked:`；`Intake#confirm` 置锁 + 追加「✅ 已确认」行；`append_text`/`handle_media` 锁定时拒收；`/new` 可解除。真实 SciNote 只读强锁（实验无 status 字段）待实例核实 → Ticket 05/08
- [ ] 设置页绑定码 UI：deface 注入"WechatGateway 绑定"面板，显示码 + 解绑（plan §14；遵守 addon 设置页须落 `addons/addon_settings` 的约定）→ 独立 Ticket，不在写入层范围

### Ticket 03 — 企微群 @ 解析 + 组长指派（F6） ✅ 核心已落地
- [x] `Message` 增加 `chat_id` / `mentions`；`wecom_message_parser.rb` 解析 `ChatId` 与 `\u0001@userid\u0001` 提及并清洗正文（**真机核实标记格式**，`inbound_spec` 覆盖）
- [x] 指派实现（**修正 plan 假设**）：宿主无 `ExperimentUserAssignment` 类，实为多态 `UserAssignment`；通过 `experiment.user_assignments.find_or_initialize_by(user:, team:)` + `UserRole.find_predefined_{normal_user,owner}_role` + `assigned: :manually` 落库（`ScinoteServiceWriter#assign_user`）
- [x] 权限校验：**实为 `can_manage_experiment_users?`**（canaid，注册于 `app/permissions/experiment.rb`），非 plan 写的 `can_manage_my_module_users?`（后者是任务级）。canaid helper 支持两参 `can_manage_experiment_users?(user, experiment)`，addon 无需 `current_user`
- [x] @ 指派接线：`Intake#assign_mentions` + 可注入 `mention_resolver`（engine 走绑定表 `find_binding`）→ 消息里的 @ 已绑定用户自动指派到当前草稿
- [ ] 任务级（MyModule）指派 + `can_manage_my_module_users?` → 与 F12「派任务」一并做（需实例核实任务 create 参数）

### Ticket 04 — 管理员查询（F9）/ 设备预约（F10） ✅ 已完成
- [x] F9：`ScinoteServiceWriter#admin_experiments(query:, team_id:, limit:)` — 前置 `InstanceAdmin.admin?(@user)`，`Experiment.joins(:project).where(projects: { team_id:, archived: false })` 跨用户直查；`/admin [关键词]` 指令
- [x] F10（**修正 plan 假设**）：SciNote **无 `EquipmentBooking` 模型**，设备预约实为 `CalendarEvent`（`event_type: :equipment_booking`，`subject` 为设备 `RepositoryRow`）。`ScinoteServiceWriter#book_equipment(row_id, start_time:, end_time:)` 前置 `Repository.equipment_booking_enabled?` + `can_create_equipment_bookings?(@user, row.repository)`，再 `CalendarEvent.create!(subject:, team: row.team, created_by: @user, ...)`；`/book <设备ID> <开始ISO> <结束ISO>` 指令
- [x] 测试：writer spec（管理员/非管理员、预约功能开关、预约权限）+ intake spec（`/admin`、`/book` 正常/参数不足/非法时间）

### Ticket 05 — 视觉识别（vision，v1 进） ✅ 已完成（识别链路）
- [x] `vision.rb`：`Vision.describe(descriptor)` 经 sidecar HTTP 端点（`VISION_ENDPOINT`）取文本；`fetcher`/`http_post` 可注入，未配置即禁用（plan §15）
- [x] `media.rb`：`Media.fetch(descriptor)` 下载媒体（iLink 走 `IlinkBridge.download_media` 解密；URL 直取；仅 media_id 的企微素材待 Ticket 07）
- [x] `Intake#handle_media`：图片识别成功 → 追加「图片识别：<text>」入正文；失败/未配置 → 降级为仅附件（plan §12.3）
- [x] 测试：`vision_spec`（启用/禁用/降级/解析）、`media_spec`（URL/iLink/降级）、`intake_spec`（识别成功/失败/未配置）
- [ ] **媒体真实附件落库**：`Experiment` 正文不支持内嵌图片（`TinyMceImages` 未含 Experiment，`RICH_TEXT_FIELD_MAPPINGS` 无 Experiment），需建任务 `Result`/`Asset` 落文件 → Ticket 08 真机核实（v1 `upload` 仅正文占位）

### Ticket 06 — AI 结构化抽取（F12，增强） ✅ 已完成
- [x] `ai_processor.rb`：LLM（OpenAI 兼容，JSON mode）抽取 → `StructuredRecord`（components/process_params/results/notes）；`llm` 可注入，未配置端点即禁用
- [x] `formulation_writer.rb`：落 **ai_eln** `Scinote::AiEln::Formulation`（**修正 plan 假设**：非 wechat_gateway 自有模型，而是复用 ai_eln addon 的一等实体）。硬约束：Formulation 需 team/created_by/name；`FormulationComponent` 必须挂宿主 `RepositoryRow`（需 `material_resolver`，无匹配则跳过不伪造）+ amount/unit；`FormulationProperty` 需 measured/target 值。ai_eln 未加载或落库失败 → no-op 返回 nil
- [x] GLP：原文完整保留 + 标「AI 辅助整理 · 需人工审核」，默认只写草稿；抽取失败降级为原文落库（不阻塞）
- [x] `ScinoteServiceWriter#persist_formulation` 委托；`Intake#append_text` AI 分支；engine 仅 `WECHAT_GATEWAY_AI_ENABLED=true` 且配置 `AI_ENDPOINT` 时注入
- [x] 测试：`ai_processor_spec`（enabled/parse/format/extract 降级）、`formulation_writer_spec`（stub ai_eln 常量；跳过不完整项/未加载 no-op/异常降级）、`intake_spec`（AI 成功/失败降级/未配置）
- [ ] 组件 → `RepositoryRow` 的**物料名匹配**（material_resolver）需真实物料库，v1 默认不注入 → 组件不落库（仅 Formulation + 性质）；真机接物料检索见 Ticket 08

### Ticket 07 — 语音 / asr（推后）
- [ ] Whisper 转写；失败降级为音频附件

### Ticket 08 — 联调与验证
- [ ] mock service 跑通全链路：绑定→建实验→追加→上传→指派→查指派→设备预约
- [ ] 真实实例起来后端到端冒烟（plan §8 阶段 5）

---

## 2. 质量门禁与命令（PowerShell）

```powershell
# 跑 addon 测试（按 Ticket 00 决定用 rspec 还是 minitest）
bundle exec rspec spec/addons/wechat_gateway        # 推荐（仓库自动挂载）
# 或（若保留 minitest）
bundle exec rake test TEST=addons/wechat_gateway/test/intake_test.rb

# 风格 + 安全
bundle exec rubocop addons/wechat_gateway
bundle exec brakeman
```

每次开发前自检（见 `addon-dev-workflow.md` 第四章）：改动全在 `addons/wechat_gateway/` 内、Gemfile 注册、枚举走 `Extends` 合并、权限落 `app/permissions/`、自带测试、ADR 更新、`rubocop`+`brakeman`+测试全绿。

---

## 3. 风险与待实例核实项（阻塞 Ticket 02/03）

1. ~~`Experiments::CreateService#call(user:, params)`~~ **已实测（Ticket 01）**：真实入口为 `CreateExperimentService.new(user, team, params).call`，`created_by`/`last_modified_by` 由服务置为传入 `user`，审计链正确。剩余待核实：① 绑定用户须对默认项目有 `EXPERIMENTS_CREATE` 权限（否则服务内部 rollback）；② `description` 富文本格式（当前纯文本拼接是否会被前端视为 HTML 转义）。
2. 草稿 `/confirm` 锁定语义（SciNote 实验无 status 字段；v1 用 `/done` 正文时间戳行表达，待评估 read_only/archive 方案）。
3. ~~指派 create 参数与 `can_manage_my_module_users?` 权限~~ **已实测（Ticket 03）**：实验级指派走多态 `UserAssignment` + `can_manage_experiment_users?`（两参形式）。剩余：任务级（MyModule）指派与 `can_manage_my_module_users?` 待 F12 核实。
4. 企微群 @ 标记格式：v1 按会话存档 `\u0001@userid\u0001` 实现，**待真机 `/wechat_gateway/wecom/callback` 抓包确认**（字段名/编码可能随协议变化）。
5. 本地 SciNote 实例未起（C 盘满 / Docker 未装）——`intake_spec`/`scinote_service_writer_spec` 用 FakeBackend + instance_double 已可无实例跑绿；真机联调见 Ticket 08。
6. 写入层为进程内强耦合，SciNote 升级时 service 签名变化需同步 addon。
7. 媒体真实附件挂接（ActiveStorage / `Uploads` 模型）未实现，v1 `upload` 仅正文占位 → Ticket 05。

---

## 4. 建议执行顺序

`Ticket 00`（测试框架决策）→ `Ticket 01`（写入层 + mock 测试，核心阻塞项）→ `Ticket 02`（/bind + /confirm）→ `Ticket 03`（群@+指派）→ `Ticket 04`（F9/F10）→ `Ticket 05/06/07`（增强）→ `Ticket 08`（联调）。

**进度**：Ticket 00/01/02（核心）/03（核心）/04/05（识别）/06（AI 抽取）已完成。已落地：写入层 intake、`/bind` 链路、`/confirm` 草稿软锁、群 @ 解析 + 实验级指派、F9 管理员查询、F10 设备预约、vision 图片识别 + 媒体下载 seam、AI 结构化抽取 + Formulation 落库。**下一步 Ticket 07**（语音 asr + 回包投递）/ **Ticket 08**（联调）。届时先在本机起 SciNote 实例，把媒体真实附件、物料匹配、群 @ 格式、富文本、回包投递真机验证。

> 所有写入层/指派/查询/预约/识别/AI 实现均已用内存 FakeBackend + `instance_double`/`stub_const` 跑通（无实例依赖）；真机联调仍需 Ticket 08。
