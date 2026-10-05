# 微信 → SciNote（scinote-web-develop）集成：需求整理与实现计划

> 目标系统：`F:\eln\scinote-web-develop`（SciNote Web 自托管二次开发实例，已含 AI-ELN Engine 与 Formulation 一等实体）
> 集成对象：原 `F:\eln\wechat_to_elabftw`（微信录入网关，对接 eLabFTW）
> **架构决策（2026-09-10）：改为 SciNote addon（进程内 Rails Engine）**，不再做独立 Python 网关。命名空间 `Scinote::WechatGateway`，落地于 `scinote-web-develop/addons/wechat_gateway`。
> 状态：需求与架构已定，计划转向 addon 实现；历史写层代码（eLabFTW 适配）保留在 `wechat_to_elabftw` 作逻辑参考，不并入 addon。

---

## 0. 架构决策记录（2026-09-10）

**选定方案：addon 化（进程内 Rails Engine）**。

理由（相对原计划「独立 Python 网关 + Doorkeeper OAuth2」）：
- 进程内直调 SciNote service / 模型，**免逐用户 OAuth token**——绕开 F3/F8 绑定复杂度；映射只存 `wechat_id → scinote_user_id`，不再存 JWT。
- F9/F10 在 addon 内可直接用模型 / 新增端点落地，不再受 v1 OAuth 子集缺口限制（见 §5.1）。
- 企微 / iLink webhook 回调直接成为 SciNote 域下的 HTTPS 路由，**免独立网关端口 + TLS 反代**。
- 代价：网关须用 **Ruby/Rails** 重写（现 Python 桥接层逻辑可移植，企微 AES-256-CBC 验签与 iLink 客户端需 Ruby 实现；AI 视觉/语音若依赖 Python 库需进程间调用）；与 SciNote 内部耦合更紧，升级需注意；受引擎约束（`isolate_namespace`、路由 append 不可覆盖核心、须 `Scinote` 命名空间）。

addon 能力边界与零入侵机制（一手调研）：`scinote-web-develop/docs/SciNote-官方扩展点调研.md`、`docs/addons-zero-intrusion.md`、ADR-0005；本仓库现有范例 `addons/ai_eln`。注册约定：宿主 `Gemfile` 一行 `gem 'scinote_wechat_gateway', path: 'addons/wechat_gateway'`，路由由 addon 自身 `engine.rb` 的 `routes` initializer 自注册，宿主 `config/routes.rb` 零修改。

---

## 1. 背景与目标

把微信群 / 私聊里的实验记录，自动落到 SciNote 电子实验记录本里，并支持"组长派任务给组员"。两条核心诉求：

1. **身份对应 + 代录**：在私聊 @机器人 或群聊 @机器人 时，获取微信用户身份 → 对应到 SciNote 里的具体用户 → 实验记录**记到该用户名下**（审计链真实）。
2. **任务指派**：组长可以把任务指派给某个组员（在 SciNote 里体现为 experiment / task 的 user assignment）。

---

## 2. 必须先决策的技术约束（已核实）

### 2.1 微信"群内 @机器人"走不通 iLink
- 实测结论（2026-08-24）：iLink bot 是独立身份，平台侧**不向 bot 投递普通微信群事件**，bot 一般也进不了普通群。私聊 DM 已真机验证可用，群聊不可行。
- 因此群聊 + @ + 多人 + 派任务这条线，必须换通道：**企业微信自建应用**（官方、合规、能收群消息含文件/图片/@）。
- **决策（已确认）**：采用**企业微信 + iLink 双通道**。两条入口在 addon 内统一收敛到同一个 SciNote 写入层。

### 2.2 SciNote 认证 = Doorkeeper OAuth2（事实仍成立，但 addon 下含义变化）
- `config/initializers/doorkeeper.rb:112` → `grant_flows %w(authorization_code)`，无 password / client_credentials；token 为 JWT（`Api::CoreJwt`），2h 过期，`use_refresh_token` 开启；`experiments_controller#create` 强制 `created_by: current_user`。
- **addon 下含义变更**：原"以某人名义建记录 = 用那人 token 调 API，网关须持每人 token"在 addon 中**不成立**。addon 与主应用同进程，可 `Experiments::CreateService.call(user: <真实 SciNote 用户>, ...)` 等以 `user:` 参数直置 `created_by`，**无需任何 OAuth token**。绑定只需确认"微信用户 = 该 SciNote 用户"，不依赖 OAuth 授权码（见 §6/§14 改为应用内绑定码）。Doorkeeper 事实仍保留作参考（§13）。

### 2.3 v1 API 受开关保护（addon 下基本无关）
- `config/routes.rb:1153` 的 `namespace :v1` 受 `ENV['CORE_API_V1_ENABLED']` 控制（`config/initializers/api.rb:12`）。
- addon 进程内调 service / 模型，**不经 `/api/v1` HTTP**，故该开关对写入无影响。仅当 addon 对外暴露 JSON 端点给第三方时才需要。事实保留备查。

---

## 3. 需求清单

### 3.1 功能需求
| 编号 | 需求 | 说明（addon 方案） |
|---|---|---|
| F1 | 私聊 @bot 获取微信用户身份 | iLink DM，拿到微信 user_id / 昵称 |
| F2 | 群聊 @bot 获取微信用户身份 | 企业微信自建应用，拿到成员 userid / 姓名 |
| F3 | 微信用户 ↔ SciNote 用户映射 | addon 自带迁移表 `wechat_user_bindings(wechat_id, scinote_user_id, platform)`，**不存 token** |
| F4 | 以用户名义建实验记录 | addon 调 `Experiments::CreateService.call(user: <真实用户>, ...)`，`created_by` 自动为该用户 |
| F5 | 文本/图片/文件/语音落库 | Ruby 化现有 intake 逻辑（正文追加、附件上传、语音转写、图片视觉识别） |
| F6 | 组长指派任务给组员 | addon 以组长 `scinote_user` 上下文校验 `can_manage_my_module_users?` 后调指派 service |
| F7 | 指令系统 | `/new` `/use <ID>` `#<ID> 文本` `/done` `/cancel` 等 Ruby 化沿用 |
| F8 | 身份绑定引导 | addon 内"绑定码"流程：SciNote 设置页显示一次性码，用户发 `/bind <码>` 确认；无需 OAuth |
| F9 | 管理员查询用户实验与任务进展 | addon 内以管理员上下文直查模型（跨用户），**addon 内可行** |
| F10 | 设备预约 | addon 内直用 `EquipmentBooking` 模型或新增 JSON 端点，**addon 内可行**（原 v1 缺口已消解） |

### 3.2 非功能需求
- **审计链正确**：记录必须落在真实操作人名下（addon 以 `user:` 参数置 `created_by`），符合 GLP。
- **绑定安全**：绑定码须一次性 + 过期 + 与生成时 SciNote session 用户绑定，防冒领（见 §14）。
- **通道无关**：iLink 与企业微信两条入口只负责"取身份 + 收消息"，下游写入逻辑完全共用。
- （原"多用户 token 加密存储"要求已消除——addon 不持有任何 OAuth token。）

### 3.3 已确认需求基线（2026-09-09 产品方确认，2026-09-10 适配 addon）
| 维度 | 确认结论 | 对范围的影响 |
|---|---|---|
| v1 范围 | 含企微群聊 + 组长派任务（双通道全量） | 企微自建应用 + 群/@ 解析 + 指派为 v1 必需 |
| 代录合规 | 草稿 + 确认两阶段：addon 以真实用户建草稿，本人 `/confirm` 才正式锁定 | 绑定（F8）+ 草稿/确认为 v1 必需 |
| 内容形态 | 先文本后增强：v1 原文保真落库，AI 结构化抽取为后续增强 | `ai_processor` 不进 v1 关键路径，架构预留接入点 |
| 媒体 | 文本 + 图片（语音转写推后） | v1 接 vision 视觉识别；asr 推后 |

**addon v1 必需模块**：`wecom_bridge`(Ruby) + `ilink_bridge`(Ruby)、`binding_resolver` + 绑定码 UI（F3/F8）、`intake`(Ruby) 抽 `Backend` 接口并接 `scinote_service_writer`、`experiment_writer`(service 封装)、草稿创建 + `/confirm` 锁定、企微群 @ 指派（F6）。F9/F10 一并纳入 addon（原"第二阶段阻塞"已消除）。

**明确推后（增强）**：语音/asr 转写、`ai_processor` 结构化抽取进 Formulation 实体、`user_identities` 反向映射。

---

## 4. 架构设计（addon 进程内 → 统一写入层）

```
[微信私聊]  ── iLink bot (DM) ──────────┐
                                        ├─► [addon 统一 Message] ─► binding_resolver(wechat_user_bindings)
[企业微信群]── 企微自建应用(@+群消息) ───┘                                  │
                                                                          ▼
                                   [WechatGateway Engine 控制器] ── 直调 SciNote service / 模型（同进程）
                                   （回调路由经 engine.rb routes initializer 挂到 SciNote 域：/wechat_gateway/*）
                                          ├─ Experiments::CreateService / Tasks / UserAssignments（F4/F6）
                                          ├─ EquipmentBooking（F10）
                                          └─ 管理员跨用户查询（F9，直查）
```

- **入口层（2 个，Ruby）**：`ilink_bridge`（私聊）、`wecom_bridge`（企微：验签 + AES 解密 + 媒体下载 + 群/@ 解析）。
- **统一抽象**：两者产出统一 `Message(user_id, text, media[], type)` 交给 `intake`。
- **写入层**：`intake` 路由/会话草稿 → `scinote_service_writer` 封装 `Experiments::CreateService` 等 service 调用，置 `created_by=真实用户`。

---

## 5. SciNote 服务端契约（service / 模型层参考）

> addon 进程内调用，下表为对应 service / 模型与关键参数（HTTP v1 仅作语义参考；实现走 Ruby service object，不经 `/api/v1`）。

| 用途 | 调用方式（addon 内） | 关键参数 | 语义依据 |
|---|---|---|---|
| 建实验（记到真实用户名下） | `Experiments::CreateService.call(user:, params)` | `params: {team_id, project_id, name, description, status, ...}`；service 置 `created_by: user` | `experiments_controller.rb:25-32`（同语义） |
| 查/列用户 | `User.find` / `User.where` | — | — |
| 实验级指派 | `ExperimentUserAssignment` service / `create` | `user_id, user_role_id` | `experiment_user_assignments` 路由 |
| 任务级指派 | `TaskUserAssignment` service / `create` | `user_id, user_role_id`, `assigned: :manually` | `task_user_assignments_controller.rb` |
| 建任务 | `Tasks::CreateService.call(user:, params)` | `name, description, ...` | `tasks_controller.rb` |
| 设备预约（F10） | `EquipmentBooking.create!(user:, equipment_id:, start_time:, end_time:)` | 直用模型 | `config/routes.rb:1274`（模型在 v1 外，addon 内可直接用） |
| 管理员查询（F9） | 管理员 `user` 上下文直查 `Experiment.where(...)` 等 | 按 team / user scope | 无 v1 端点，addon 内自实现 |

**注意**：指派 `create` 语义（service 参数与权限）需在实例起来后对照 `task_user_assignments_controller` / `experiment_user_assignments_controller` 的 `create` action 实测确认（本次只读了 update）。

### 5.1 F9/F10 在 addon 内可行（2026-09-09/10 核实结论，已消解缺口）
- 原"v1 子集缺口"结论（F10 不在 v1、F9 无管理员端点）**对 addon 方案不再构成阻塞**：addon 进程内不经 `/api/v1`，可直接用 `EquipmentBooking` 模型与跨用户查询。
- F10：addon 控制器/服务直接 `EquipmentBooking.create!`，或按需在 addon 内新增 JSON 端点（append，不覆盖核心）。
- F9：addon 以管理员 `user` 上下文直查，或新增管理员列举 action。

---

## 6. 用户映射与身份方案（addon 表 + 绑定码）

- addon 自带迁移表 `wechat_user_bindings`：
  ```ruby
  create_table :wechat_user_bindings do |t|
    t.string :wechat_id,   null: false   # 微信/企微 userid
    t.string :platform,    null: false   # 'ilink' | 'wecom'
    t.bigint :scinote_user_id, null: false
    t.string :status, default: 'active'
    t.timestamps
  end
  add_index :wechat_user_bindings, [:wechat_id, :platform], unique: true
  ```
- **绑定流程（F8，非 OAuth）**：用户在 SciNote 设置页（addon 经 deface 注入"微信绑定"面板）看到一次性绑定码 → 微信发 `/bind <码>` → addon 校验码归属生成时的 SciNote session 用户 → 写 `wechat_user_bindings`。全程不触碰 Doorkeeper（见 §14）。
- 可选：同时在 SciNote `user_identities` 补 `provider:'wechat', uid:<微信ID>` 便于反向查表与审计。

---

## 7. 任务指派流程（F6，addon 上下文）

1. 组长在企业微信群 @bot：`指派 @张三 做 #实验42 的任务「样品前处理」`。
2. 企微入口解析：指令人=组长（其 `scinote_user_id`），目标人=@张三（映射），目标实验/task。
3. addon 校验组长对该 experiment/task 有 `manage_users` 权限（`can_manage_my_module_users?`）。
4. 以组长 `user` 上下文调指派 service，把目标 user 以指定 `user_role` 挂到 experiment / task；SciNote 自动写 `Activity` 审计。
5. 回执："`✅ 已把 张三 指派到 实验#42 / 任务「样品前处理」`"。

---

## 8. 分阶段实施计划（addon 化）

### 阶段 0：addon 脚手架 + 注册
- [ ] `rails generate addon Scinote::WechatGateway`（或按骨架手写）；产出 `addons/wechat_gateway/`。
- [ ] 宿主 `Gemfile` 加 `gem 'scinote_wechat_gateway', path: 'addons/wechat_gateway'`（零入侵启用开关）。
- [ ] `engine.rb` 自注册路由 `mount Scinote::WechatGateway::Engine => '/wechat_gateway'`。
- [ ] `db/migrate` 建 `wechat_user_bindings` 表。

### 阶段 1：绑定层（F3/F8）
- [ ] `binding_resolver`：按 `wechat_id+platform` 查 `scinote_user_id`；未绑定触发引导。
- [ ] 绑定码生成 + 校验 + 设置页 deface 面板（`/bind <码>`）。
- [ ] 写 `wechat_user_bindings`。

### 阶段 2：写入层（F4/F5，草稿 + 确认）
- [ ] Ruby `intake`：指令路由 / 会话草稿。
- [ ] `scinote_service_writer`：封装 `Experiments::CreateService` 等，置 `created_by=真实用户`。
- [ ] 草稿创建 → 本人 `/confirm` 锁定（状态语义待实例核，见 §5 注）。

### 阶段 3：企微 / iLink 桥接（F1/F2）
- [ ] `wecom_bridge`（Ruby）：回调验签 + AES-256-CBC 解密 + 媒体下载 + 群/@ 解析（技术要点见 §9）。
- [ ] `ilink_bridge`（Ruby）：iLink DM 长轮询收消息。
- [ ] 两者统一 `Message` → `intake`。

### 阶段 4：指派 / 查询 / 设备预约（F6/F9/F10）
- [ ] F6 组长指派（§7）。
- [ ] F9 管理员查询（addon 内直查）。
- [ ] F10 设备预约（addon 内 `EquipmentBooking`）。

### 阶段 5：联调与验证
- [ ] 用"忠实复刻 SciNote service 行为"的 mock / 本地实例，跑通：绑定→建实验→追加→上传→指派→查指派→设备预约。
- [ ] 真实实例起来后做端到端冒烟。

---

## 9. 企业微信 API 接入技术要点（wecom_bridge Ruby 实现参考）

> 企业微信不走 iLink 协议，使用自有官方开放接口。以下为对接关键技术点（细节以官方文档 + 真实回调核对为准）。

### 9.1 凭证与 access_token
- `corpid` / `corpsecret` / `agentid` 在企微管理后台「应用管理 → 自建」获取。
- `access_token`：`GET qyapi.weixin.qq.com/cgi-bin/gettoken` → 7200s 过期，需缓存 + 刷新。收消息**不需要** access_token；主动调 API（下载媒体、被动回复）才需要。

### 9.2 回调验签 + AES 解密（收消息核心）
- 配置回调 URL 时企微先发 **GET 校验**（`msg_signature/timestamp/nonce/echostr`），需验签并解密 `echostr` 原样返回。
- 正式消息为 **POST**，Body 为 XML（`<Encrypt>` 包裹密文）。
- 验签：`msg_signature = sha1(sort([token, timestamp, nonce, encrypt]))` 比对。
- 解密（`EncodingAESKey`，43 字符）：`AESKey = base64decode(EncodingAESKey + "=")` → 32 字节；`IV = AESKey[:16]`；`AES-256-CBC`，PKCS7 去填充；明文 = `random(16) + msg_len(4,大端) + msg + receiveid(corpid)`。
- 解析 `msg`（XML）：`FromUserName`(成员 userid) / `MsgType` / `Content` / `AgentID` / `MsgId`；**群聊带 `ChatId`**。

### 9.3 私聊 vs 群聊 + @解析
- 私聊：无 `ChatId`，`FromUserName` 即发消息成员 → 直接"以该用户名义建记录"。
- 群聊：有 `ChatId`，`Content` 含 @信息（企微群 @ 文本内嵌 `\u0001@userid\u0001` 风格标记，以真实回调核对）→ 定位被指派组员。

### 9.4 媒体下载
- 图片/文件/语音带 `MediaId`；`GET qyapi.weixin.qq.com/cgi-bin/media/get?access_token=TOKEN&media_id=ID` 下载后落本地，经视觉识别/转写再上传 SciNote。

### 9.5 与 iLink 的差异
| 项 | iLink（私聊） | 企业微信（群聊+派任务） |
|---|---|---|
| 收消息 | 长轮询 `get_updates` | HTTPS 回调 webhook（验签+AES） |
| 群事件 | 平台不投递 | 官方支持（带 `ChatId`） |
| 加解密 | AES-128-ECB（SDK 内置） | AES-256-CBC（需自实现） |
| 身份 | 微信昵称/openid | 企业 `userid`（稳定，直接映射） |

---

## 10. 风险与待确认

1. **指派 create 语义**：本次只核对 `task_user_assignments#update`；新建指派 service 参数与权限需实例实测（§5 注）。
2. **addon 与 SciNote 内部耦合**：升级 SciNote 时 service / model 签名变化可能需同步 addon；decorator 谨慎使用。
3. **群聊仅企微，iLink 仅私聊**：群场景强依赖企微。
4. **企微 webhook 须公网 HTTPS**：回调挂在 SciNote 域下（`/wechat_gateway/*`），仍需域名 + 证书（SciNote 本身已 TLS，无额外反代）。
5. **绑定码安全**：须一次性 + 过期 + 绑定生成时 SciNote session 用户，防冒领（§14）。
6. **C 盘满 / Docker 未装**：本地起 SciNote 实例受阻，建议先用 mock service 联调（同 8/24 做法）。
7. **F9/F10 已通过 addon 解决**：原 v1 子集缺口不再阻塞（§5.1）。
8. **AI 视觉/语音依赖**：若依赖 Python 库（Whisper/vision），addon 内需 sidecar 进程或 Ruby 移植。

---

## 11. 下一步
- **立即**：脚手架 addon（已建骨架：`engine.rb` / `gemspec` / `routes` / 控制器 / 模型 / 迁移）+ 宿主 `Gemfile` 一行。
- 参考 `wechat_to_elabftw` 的 Python 逻辑（intake / wecom_bridge / ilink_bridge / ai_processor）移植到 Ruby。
- 待实例可用后：补 `@confirm` 状态语义、指派 create 实测、绑定码 UI（deface）。

---

## 12. AI 加工层设计（接收 → AI 加工 → 写入 ELN）

> 需求：企微消息先经 AI 加工（结构化抽取）再写入 SciNote。插在 `intake` 与 `scinote_service_writer` 之间，对应 `ai_processor`（Ruby 实现或调用 Python sidecar）。

### 12.1 处理链路
```
企微/微信消息 → bridge(收+验签+解密+媒体下载)
             → 统一 Message(user_id, text, media[])
             → intake(指令路由/会话草稿)
             → ai_processor(多模态归一 + LLM 结构化抽取 + GLP 标记)
             → scinote_service_writer(写 SciNote service)
```
### 12.2 职责
1. 多模态归一：文本直用；语音→`asr`(Whisper) 转写；图片→`vision` 本地识别取文字/读数。
2. LLM 结构化抽取：DeepSeek/OpenAI 兼容端点，JSON mode 输出固定 schema（对应 SciNote **Formulation** 实体：`components`→`FormulationComponent`，`results`→`FormulationProperty`）。
3. GLP 合规：原始消息原文**完整保留**；AI 结果标"需人工审核"；默认先写草稿，`/confirm` 锁定。
### 12.3 接入与降级
- Ruby 直接调 LLM（OpenAI 兼容）；图片不直传 LLM（兼容坑）→ 经 `vision` 取文字再送。
- 失败降级：LLM/视觉不可用退回"原文保真落库"，不阻塞录入。
- 与 SciNote 内置 AI-ELN Engine 分工：网关 AI 做结构化抽取写入；SciNote AI-ELN 做后续语义检索与关联。

---

## 13. Doorkeeper 事实参考（addon 绑定改为绑定码，本节约参考）

> 以下为 SciNote 实例侧 Doorkeeper 事实（2026-09-09 核实源码），保留作外部集成参考；**addon 方案不依赖 OAuth 绑定**（见 §6/§14）。

### 13.1 `core_api_v1_enabled`
- `config/initializers/api.rb:12`：`ENV['CORE_API_V1_ENABLED'] || false`；设任意非空即开。addon 内调用不经 HTTP v1，无影响。

### 13.2 Doorkeeper 应用注册（无后台 UI）
- `config/routes.rb:2-4`：`skip_controllers :applications` → 无网页注册；须 `rails console` / `db/seeds.rb`：
  ```ruby
  app = Doorkeeper::Application.create!(
    name: 'WeChat Gateway', redirect_uri: 'https://<域>/oauth/callback',
    scopes: 'public')
  ```
- `default_scopes :public`；`grant_flows %w(authorization_code)`；`use_refresh_token` 开。

### 13.3 Token 机制
- access token = JWT(HS256)，`payload={sub:user_id, exp:2h后, iss:'SciNote'}`；`Authorization: Bearer <JWT>` 解 `sub` 找 `User`。
- 续期：`POST /oauth/token` `grant_type=refresh_token`。

### 13.4 回调 HTTPS 约束
- `doorkeeper.rb:84` `force_ssl_in_redirect_uri !Rails.env.development?` 默认开 → prod 下 OAuth 回调须 HTTPS（addon 绑定不走 OAuth，故不适用）。

---

## 14. 用户绑定流程详述（绑定码，非 OAuth）

绑定 = 应用内"一次性绑定码"确认；因 addon 进程内可直置 `created_by`，无需 OAuth token。

### 14.1 时序
1. **生成码**：用户在 SciNote 设置页（addon deface 注入"微信绑定"面板）点"生成绑定码" → addon 以**当前登录用户** `current_user` 生成一次性码（存库/缓存，含 `scinote_user_id`、过期时间）。
2. **发码**：面板显示码（如 `WX-AB12CD`）；用户复制到微信/企微发给 bot。
3. **确认**：bot 收 `/bind WX-AB12CD` → addon 验码有效且未过期 → 写 `wechat_user_binding(wechat_id: <发消息微信用户>, platform:, scinote_user_id: <码归属用户>)`。
4. **回执**："`✅ 已绑定 SciNote（用户 X），以后记录记到你名下`"。

### 14.2 要点
- 码与生成时的 `current_user` 强绑定 → 冒领者拿码也只能绑到自己 SciNote 身份（或码过期）；比 OAuth state 更简单且进程内安全。
- 换绑/解绑：设置页提供"解绑"清除 `wechat_user_binding`。
- 移动端小坑：微信内点设置页可能开内置浏览器，必要时提示"用系统浏览器打开"（不影响正确性）。

---

## 15. 部署拓扑（addon 进程内）

**结论：addon 随 SciNote 同进程部署，无独立网关进程**。
- 回调路由 `/wechat_gateway/*` 在 SciNote 域下，复用 SciNote 已有 TLS；**无需独立端口 + 反代**。
- 企微/微信 webhook 仍须公网 HTTPS，但指向 SciNote 域名（已具备），仅路径为 `/wechat_gateway/wecom/callback`。
- 媒体/AI 处理：纯 Ruby 时随 SciNote 进程；若用 Python AI 库，起一个 sidecar 由 addon 内部 HTTP 调用。
- 绑定：用户在 SciNote 设置页完成，无需网关回调域。
