# AI & Automations 二次开发计划（addon 形态）

> 依据：官网 https://www.scinote.net/product/ai-and-automations/ 三大模块 + 代码库现状探查 + **grilling 已确认决策**（见第三节）。
> 方法学：`docs/agents/addon-dev-workflow.md`（Phase 0–6）。已加载技能：`codebase-memory`（探查）、`mattpocock-skills`（grill → TDD → ADR → to-issues）。
> 状态：✅ 已 grill 确认；本文件即 PRD + Issues 拆分，可直接进入 `/implement`。

---

## 一、官方功能 × 项目现状（已核实源码）

| 官方模块 | 项目现状 | 结论 |
|---|---|---|
| **Workspace Automations** | 已完整实现：`app/services/automation_observers/`（9 observer）、`Extends::TEAM_AUTOMATIONS_GROUPS` / `TEAM_AUTOMATIONS_OBSERVERS_CONFIG`、`app/javascript/vue/team_automations/`、`teams/automations.html.erb`、`MyModuleStatusConsequences::Completion/Uncompletion` | 存量能力；本 fork 直接可用，二次开发以 **addon 扩展自定义规则** 形式进行 |
| **Create with AI** | 仅预留开关：`Protocol.ai_parser_enabled?`（`app/models/protocol.rb:293`）全仓无消费方；`AI_PROTOCOLS_PARSER` ENV 预留；无 LLM 客户端/服务/UI | **绿地**——本期 MVP |
| **Import with AI（Beta）** | 未实现；可与 Create with AI 共用 LLM 解析服务，复用 `protocols_controller#import` | 与 Create with AI 合并实现 |

---

## 二、已核实技术接缝

- **A — 协议持久化（核心插入点）**：`app/services/protocol_importers/import_protocol_service.rb`
  `ImportProtocolService.call(protocol_params:, steps_params_json:, team:, user:)` 在事务内建 `Protocol`+`Step`+顺序元素。每步 schema：`name`/`position`/`description`/`tables_attributes`/`assets`。AI 生成 JSON 对齐此 schema 即可落库，**不碰核心创建逻辑**。
  ```18:22:scinote-web/app/services/protocol_importers/import_protocol_service.rb
      def call
        return self unless valid?
        ActiveRecord::Base.transaction do
          @protocol = Protocol.create!(@protocol_params.merge!(added_by: @user, team: @team))
  ```
- **B — 功能开关（复用，不新建）**：`Protocol.ai_parser_enabled?` 消费 `ENV['AI_PROTOCOLS_PARSER']` + `ApplicationSettings#values['ai_protocol_parser_enabled']`（迁移已置 `true`）。
  ```293:295:scinote-web/app/models/protocol.rb
      def self.ai_parser_enabled?
        ENV.fetch('AI_PROTOCOLS_PARSER', nil).present? && ApplicationSettings.instance.values['ai_protocol_parser_enabled'] == true
      end
  ```
- **C — 导入路径**：`protocols_controller#import`（`app/controllers/protocols_controller.rb:613`）→ `@importer.import_new_protocol`。
- **D — 权限**：addon 的 `app/permissions/**/*.rb` 被 `config/initializers/canaid.rb` 自动发现。
- **E — 前端/视图**：核心协议创建页挂 "Create with AI" 入口，走 `app/decorators` / `app/overrides`（deface）覆盖，受 `ai_parser_enabled?` 门控。

---

## 三、Grilling 已确认决策

1. **LLM 接入 = OpenAI 兼容 API**（含官方 OpenAI 与 Azure OpenAI）：用 Chat Completions + 结构化输出（JSON schema 约束）。
   - `AI_PROTOCOLS_PARSER` 语义明确为 **OpenAI 兼容 base URL**（Azure 用其 endpoint）。
   - 新增可选配置 `AI_PROTOCOLS_MODEL`（模型名，默认 `gpt-4o-mini` 级）。
   - `LlmClient` 用策略模式，未来可加 Claude/Ollama 而不改调用方。
2. **本期范围 = 三块全做**，优先级：Create with AI（MVP）→ Import with AI（复用同一 generator）→ Automations 扩展（先 spike）。
3. **协议落点 = 协议模板草稿（draft template）**：AI 生成内容先存为可审核/编辑的协议模板草稿，用户确认后再导入项目。契合官网描述、风险最低。

---

## 四、PRD

**目标（In scope）**
- 用户粘贴文本 / 上传 PDF/SOP → 经 OpenAI 兼容 LLM 生成结构化协议（步骤含文本/表格/检查清单）→ 落为**协议模板草稿**供审核编辑。
- "Import with AI" 复用同一生成服务，从导入入口触发。
- 以 addon 形式扩展 Workspace Automations，支持团队自定义自动化规则（spike 后定型）。

**非目标（Out of scope，本期）**
- 不改核心 `app/` 任何文件（铁律）；覆盖核心行为一律走 addon 的 `app/decorators` / `app/overrides`。
- 不实现多模态/图像理解（PDF 先抽取文本再送 LLM）。
- 不替换上游已有的 automations 状态机，只在其上叠加可插拔规则。

**用户故事**
- 作为实验室经理，我想把内部 SOP（PDF）一键转成 SciNote 协议模板，减少复制粘贴。
- 作为研究员，我想用自然语言描述实验流程，AI 生成带表格/检查清单的协议草稿供我修订。
- 作为团队管理员，我想在现有 Automations 之上加一条自定义规则（如"某状态自动通知某角色"）。

---

## 五、Issues 拆分（垂直切片，可独立 grab）

> 每个 Issue 单独开 session 走 `/implement`（内部 `/tdd` 红绿），合入前 `/code-review`（Standards + Spec）。

### Addon `addons/ai_protocols`（isolate_namespace `Scinote::AiProtocols`）

- **Issue A1 — LLM 客户端适配器** `Scinote::AiProtocols::LlmClient` ✅ 完成
  - OpenAI 兼容 Chat Completions，支持 `base_url`/`api_key`/`model`；强制 `response_format` JSON schema。
  - 文件：`addons/ai_protocols/lib/scinote/ai_protocols/llm_client.rb`（ENV 读取在 `LlmClient#initialize`，功能等价于计划的 engine.rb 读取、更内聚）；`engine.rb` 负责 autoload/挂载。新增 `AI_PROTOCOLS_API_KEY`（LLM 鉴权所需，计划未列但合理）。
  - 重试/兜底：`#post` 对 5xx 与网络异常（`Net::OpenTimeout`/`Net::ReadTimeout`/`Errno::ECONNRESET`/`EOFError`）重试 `MAX_RETRIES=2` 次；4xx 客户端错误不重试、直接抛 `ApiError`（5xx 转 `RetryableApiError < ApiError`）。
  - 测试（spec）：webmock 断言请求体含 `response_format`、base_url 正确、5xx 重试至成功、4xx 不重试。
- **Issue A2 — 协议生成服务** `Scinote::AiProtocols::ProtocolGenerator` ✅ 完成
  - Prompt 工程：输入文本/抽取后的 PDF 文本 → 输出对齐 `ImportProtocolService` `steps_params` schema 的 JSON（name/position/description/tables_attributes）。
  - 文件：`addons/ai_protocols/app/services/scinote/ai_protocols/protocol_generator.rb`、`app/permissions/scinote/ai_protocols/permissions.rb`（`can_generate_protocol_with_ai?`）。
  - 测试：fixture 文本 → 断言生成 JSON 可被 `ImportProtocolService` 消费（结构契约测试，落 `in_repository_draft`）。
- **Issue A3 — Create with AI UI（MVP）** ← grill 决策已锁定（详见 `ARCHITECTURE_DECISIONS.md` ADR-006）
  - **落点**：`Protocol#protocol_type = :in_repository_draft`（协议模板草稿，枚举值 6），经 `ProtocolImporters::ImportProtocolService.call(protocol_params:, steps_params_json:, team:, user:)` 落库。
    - ⚠️ **修正**：A2 合同测试曾误用 deprecated 的 `in_repository_private`（值 2），须改为 `in_repository_draft`。
  - **输入**：先纯文本（PDF 抽取留接口/stub，待环境具备抽取工具再补）。
  - **预览**：自带可编辑表单（ERB + 原生 JS），用户改 name/step/table，提交才落库；不碰 webpack pack、不碰核心 JS。
  - **入口**：addon 独立 controller 闭环（`GET /ai_protocols/new` → `POST /ai_protocols/preview` 可编辑 → `POST /ai_protocols` 落库）；入口按钮用 `app/decorators` 注入协议库页。引擎已 `mount => '/`（routes.rb:16），addon 需补 `config/routes.rb`。
  - **权限**：`can_generate_protocol_with_ai?(user, team)` 基于 `can_create_protocols_in_repository?`（复数，基于 `TeamPermissions::PROTOCOLS_CREATE`，见 `app/permissions/team.rb:35`），不新增角色。
  - 全程受 `ai_parser_enabled?` 门控。
  - **拆切片（垂直、可独立 grab）**：
    - **A3a** 生成预览闭环：权限文件 + 路由 + `new`/`preview` + 可编辑表单骨架 + request spec（mock LlmClient）。✅ 完成
    - **A3b** 提交落库：`create` 调 `ImportProtocolService` 落 `in_repository_draft` + spec。✅ 完成
      - ⚠️ 引擎控制器内 `protocol_path` 须用 `main_app.protocol_path`（引擎 isolate_namespace + mount '/' 导致裸 helper 解析到引擎自身路由，否则 create 落库后 redirect 报 `UrlGenerationError`）。
    - **A3c** 入口按钮：`app/overrides` deface override 注入协议库页 `title-row` + spec。✅ 完成
      - 用 deface（已在 bundle 中，1.9.0，传递依赖，无需改 Gemfile）；override 受 `Protocol.ai_parser_enabled?` + `can_generate_protocol_with_ai?` 双门控；引擎 `to_prepare` 显式加载 `app/overrides/*.rb`。
  - 测试：request spec（mock LlmClient / ImportProtocolService）验证端到端生成草稿。
- **Issue A4 — Import with AI** ✅ 完成
  - 入口：扩展 A3 的 `new` 页，增加「上传文件」输入（`.txt/.text/.md/.markdown/.pdf`），服务端 `TextExtractor` 抽取文本后复用 new→preview→create 闭环落 `in_repository_draft`。不碰核心 `protocols_controller#import`（铁律）。
  - 文本抽取：新增 `app/services/scinote/ai_protocols/text_extractor.rb`，`.txt/.md` 直读，`.pdf` 经 `IO.popen(['pdftotext', path, '-'])`（与核心 `text_extraction_analyzer` 同方式）；`pdftotext` 缺失时抛 `ExtractionError` 而非静默；不支持类型抛 `UnsupportedFileType` 并回退 new 页带 alert。
  - 权限：复用 `can_generate_protocol_with_ai?`（即创建权限）。
  - 测试：TextExtractor 单测（5 例：.txt/.md 直读、PDF 委派、不支持类型、pdftotext 缺失）+ request spec 文件上传（.txt 抽取预览 / .pdf 委派抽取 / 不支持类型回退表单）。
  - ⚠️ 生产依赖 `poppler-utils`（`pdftotext`）；SciNote 全文搜索已依赖该命令，官方镜像通常自带，部署时需确保安装。
- **Issue A5 — 权限与全量测试** ✅ 完成
  - 权限已完整：`can_generate_protocol_with_ai?`（`app/permissions/scinote/ai_protocols/permissions.rb`）基于 `can_create_protocols_in_repository?`；在 `ProtocolGeneratorController` 经 `before_action :check_generate_permission` 覆盖 new/preview/create，并在 deface 入口按钮双门控（`ai_parser_enabled? && can_generate_protocol_with_ai?`）。反向门控测试已覆盖（无权限/禁用时隐藏按钮、new/create 返回 403）。
  - 整工程测试收口：`config/initializers/load_addons_specs.rb` 在 test/dev boot 时将 `addons/ai_protocols/spec` 符号链接到 `spec/addons/ai_protocols`。已 `mkdir -p spec/addons` 并加 `.gitkeep`（此前父目录缺失导致 initializer 误报 "symlink unsupported"）。`rspec spec/addons/ai_protocols` 全绿（24 examples, 0 failures）。
  - ⚠️ `spec/addons` 父目录须由版本库/setup 保留；initializer 每次 boot 会 `rm_f spec/addons/*` 再重建 symlink。Windows 宿主因不支持 symlink 走 fallback 分支（不影响容器内 Linux 测试，可改用 `rspec addons/ai_protocols/spec` 指名路径）。

### Addon `addons/automations_ext`（或并入 ai_protocols，待 spike 定）

- **Issue B0 — SPIKE：Automations 扩展可行性**
  - 探查：`TEAM_AUTOMATIONS_OBSERVERS_CONFIG`（`Extends`）是否可由 addon 经 `Extends` 合并注入新 observer；`observable_model.rb` / `AutomationObservers` 的触发链如何被 addon observer 接入；`MyModuleStatusConsequences` 是否可扩展。
  - 产出：可行性结论 + 最小接入示例，决定 B1 形态。**此 Issue 必须先于 B1。**
- **Issue B1 — 自定义自动化规则**
  - 按 spike 结论，addon 注册新 observer + 新状态流后果，UI 暴露规则配置。

---

## 六、执行节奏（映射 addon-dev-workflow Phase 0–6）

- **Phase 0**：新增 ADR-00X（写入 `docs/ARCHITECTURE_DECISIONS.md` 第三节）——记录「AI 协议生成以 addon 实现、复用 `ai_parser_enabled?`/`AI_PROTOCOLS_PARSER`(=OpenAI 兼容 base URL)、LLM 客户端策略模式、JSON 对齐 `ImportProtocolService` schema、落点为 draft 协议模板」等不可逆转决策。
- **Phase 1**：探查已完成（见一二节）。
- **Phase 2**：grilling 已完成（见第三节）。
- **Phase 3**：脚手架 `addons/ai_protocols/`（复制 `addons/i18n` 骨架）+ Gemfile + routes 注册。
- **Phase 4**：按 Issues A1→A5（→B0→B1）逐条 `/tdd`。
- **Phase 5**：`rubocop addons/ai_protocols` + `brakeman` + `rspec spec/addons/ai_protocols`。
- **Phase 6**：ADR 补「与上游冲突风险」——若上游未来实现自有 AI（消费 `ai_parser_enabled?`），本 addon 的 decorator/override 可能冲突，记录覆盖点清单。

---

## 七、检查清单（开发前对照 addon-dev-workflow.md）
- [ ] 改动仅限 `addons/ai_protocols/`（及 spike 后的 `addons/automations_ext/`）
- [ ] 复用 `ai_parser_enabled?` 开关，未新建 flag；`AI_PROTOCOLS_PARSER` 作 OpenAI 兼容 base URL
- [ ] JSON 输出对齐 `ImportProtocolService` schema
- [ ] 协议落点为 draft 模板草稿
- [ ] 权限文件落在 `app/permissions/**/*.rb`
- [ ] 新增对应 ADR-00X
- [ ] rubocop + brakeman + rspec 全绿
