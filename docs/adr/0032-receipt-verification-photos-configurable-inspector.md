# ADR-0032：材料类到货验收 —— 照片 ＋ 可配置验货人 ＋ 分批验收 ＋ 未验货阻断

- 状态：已采纳（2026-10-06，用户逐项裁定）
- **部分修正 ADR-0030**（验货人不再「沿用终审名单」）；承接 `ADR-0029`（审批人配置）、`REQ-RES-TEST-STRIKE`（阻断与豁免范式）
- 影响面：`REQ-RES-APPROVE` / `SCN-RES-APPROVE-3`、`REQ-RES-APPROVER` / `SCN-RES-APPROVER-5`、新增 `REQ-RES-RECEIPT`
- 载体：`addons/eln_ui`（迁移 / service / model / controller）+ `ELN系统-Vue3`（详情页验收区块）

## 背景与触发

用户指令（2026-10-06）：**「审批通过后需要申请人上传到货照片，验货人员通过后入库，是否需要建立验收数据库？验货人员可配置」**，
随后追加「**有多次申请未验货 停止继续申请**」，并定「**跟测试服务未及时上传结果采用相同的处理**」。

ADR-0030 定的流程是「终审通过只**解锁**到货验收 → 项目负责人（**沿用终审名单**）点『到货验收入库』即写库存」。
缺口三处：① 入库前**没有任何证据**（照片）留痕；② 验货人**不可配置**；③ 单据停在「待验收」时
**没有机制阻止继续申请**，积压只能靠人催（ADR-0030「代价」节已预警）。

## 决策（8 项，均为用户裁定）

| # | 决策 |
| --- | --- |
| D1 | **建立验收记录表** `eln_ui_receipt_verifications`（一次请购可分多批验收） |
| D2 | 验货人是**独立的第三阶段** `receipt`，在 `eln_ui_project_approvers` 上配置（**修正 ADR-0030**） |
| D3 | 「验货人能否是申请人本人」用**独立配置开关** `eln_ui_receipt_policies.allow_self_verification`（按项目） |
| D4 | 验货**不通过 → 退回 `submitted`**，补货后**重走两级审批**（不加新状态） |
| D5 | 每批入库数量**由验货人填「本批到货数量」** |
| D6 | 到货照片 `has_many_attached` 挂在**验收记录**上（不挂申请单） |
| D7 | **未验货阻断**：同一申请人未验货申请数 ≥ 阈值 ⇒ 拦住**创建申请**；处理方式**完全复用**服务侧 strike 范式（见下） |
| D8 | 阈值是**模块级配置**（`Scinote::ElnUi.receipt_pending_block_limit`，默认 2），**不建 per-project 阈值表** |

## 关键论证：为什么需要建表

要素逐一落到既有载体，**只有「验收记录」与「自验策略」需要新表**：

| 要素 | 落点 | 新表？ |
| --- | --- | --- |
| 到货照片 | 宿主 **ActiveStorage**，`has_many_attached`（先例 `form_repository_rows_field_value.rb:19 has_many_attached :snapshot_files`） | 否 |
| 验货人 | `eln_ui_project_approvers` 加 `stage='receipt'`（`STAGES` 白名单由 `%w[group project]` 扩为三值） | 否 |
| 阻断阈值 | **模块级配置**（同 `service_result_strike_limit` 的注册方式） | 否 |
| 阻断豁免 | 复用 `ServiceStrikeWaiver` | 否 |
| **验收记录**（谁/何时/本批数量/结论/照片） | 新表 `eln_ui_receipt_verifications` | **是** |
| 自验策略（D3） | 新表 `eln_ui_receipt_policies`（每项目一行） | **是** |

**建表的决定性依据是基数**：D1 选定「可分批验收」⇒ 1 申请单 : **N** 条验收记录 ⇒ 结论挂列无处安放。
若当初选「只能验一次」，3 列即可、**零新表** —— 这是一步可回头的路（D1 是本 ADR 唯一不可逆处）。

> 📌 **核对过但不能当依据的一条**：spec L82「采购/到货验收入库 N 次」曾像在说「分批到货」，实际它在
> **V1.21 测试表征服务**变更块内，「N 次」指**服务按次计量**（该模型 V1.21 已废止）。
> **「一次请购能否分批到货」在原 spec 中并未规定**，是本轮新裁决。

## D7：与「服务未及时上传结果」的**同构**（用户明确要求）

现有范式（`REQ-RES-TEST-STRIKE`）**逐项照搬**，不另立一套：

| 要素 | 服务侧现状 | 材料侧（本 ADR） |
| --- | --- | --- |
| 计数 | `ServiceStrikeBook.for_applicant(user_id)` | `for_applicant(user_id)` 换成「未验货申请」 |
| 阈值 | `Scinote::ElnUi.service_result_strike_limit`（模块级，默认 10） | 新增 `Scinote::ElnUi.receipt_pending_block_limit`（默认 **2**） |
| 判定 | `frozen?(user_id)` = 计数 ≥ 阈值 | 同构 |
| 拦截位置 | **`create_draft`**（`resource_application_workflow.rb:75` 方法内，`:115-121`） | **同一位置** |
| 拦截对象 | 只冻**测试表征**申请（材料照常入） | 只冻**材料**申请（服务照常入）—— **镜像** |
| 豁免 | `ServiceStrikeWaiver` 放行**一次**、用后即失效、**不消解占用** | **复用同一张表与同一方法** |
| 三步序 | ⚠ 先判冻结 → 再找豁免 → 都没有才 `raise` | **同序**（顺序反了会把豁免在「没被冻结」时白白用掉） |
| 报错约定 | `block_reason` **未冻结返回 `nil`**（而非空串） | 同构（避免 `if msg.present?` 把「没冻结」当「冻结但没理由」） |
| 报错内容 | 「未回填测试表征结果占用 N 次，已达阈值 M，暂缓提交…欠交清单：…」 | 同构，列出**未验货单号** |

**为什么是镜像而不是合并成一条规则**：两者对象互补（服务侧冻服务、材料侧冻材料），
合起来才覆盖「申请类型全集」；而**机制**必须只有一份。现有代码注释已把「只冻服务、材料照常入」
的理由写死为 spec 约束（`SCN-RES-TEST-STRIKE-2`），故本轮**不改那条**、只补镜像那条。

## 数据模型

### `eln_ui_receipt_verifications`（新建）
| 列 | 含义 |
| --- | --- |
| `resource_application_id` | FK → 申请单 |
| `status` | `pending`（申请人已交照片待验）/ `passed` / `rejected` |
| `verifier_id` | 验货人（`pending` 时 nil） |
| `verified_at` | 验货时间 |
| `qty` | **本批**数量（D5） |
| `note` / `rejection_reason` | 验货备注 / 拒收理由（D4 退回时必填） |
| 审计列 | `created_by_id` / `*_at` |
| — | `has_many_attached :photos`（D6） |

不设 `round`：**第几轮可由 `created_at` 派生**，可算的不存（本项目一贯口径）。

### `eln_ui_receipt_policies`（新建，每项目一行）
| 列 | 含义 |
| --- | --- |
| `project_id` | 唯一索引 |
| `allow_self_verification` | D3 |
| `updated_by_id` / `updated_at` | 审计 |

> 采纳「独立开关」而非「名单隐含」，代价是多一张表；换来的是**自审策略可独立于名单调整**
> （例如名单里必须有 PI 才能让他验货，但本项目不接受他验自己的单）。

## 状态机（在既有 5 态上叠加，不新增状态）

```
draft ─submit─▶ submitted ─group─▶ group_approved ─project─▶ project_approved
                                                                  │
                                        申请人：传照片 + 本批数量  │  建 verification(pending)
                                                                  ▼
                                                    verification(pending)
                                                                  │
                                              ┌───────────────────┴───────────────────┐
                                           passed                                rejected
                                              │                                       │
                              累计已验 ≥ 申请量 ?                          退回 submitted（重走两级审批）
                                 ├─ 是 → completed                        （记录保留，审计留痕）
                                 └─ 否 → 留 project_approved（还有批次没到）
```

**收口用「数量」而非额外标志位**：每次 `passed` 累加 `qty`，≥ 申请量即 `completed`。库房数字说话，
不引入「这是最后一批吗」这种易漏的勾选。**代价**：最终到货量少于申请量时单据会长期停在 `project_approved`
—— 这正是 D7 要拦的积压形态，靠阻断 + 待办可见性兜。

## 对既有代码的改动点

| 位置 | 改动 |
| --- | --- |
| `ProjectApprover::STAGES` / `STAGE_LABELS` | 加 `receipt`（标签「验货」） |
| `ResourceApprovalPolicy` | 新增 `can_verify_receipt?`（= 在 `receipt` 名单 **且**（允许自验 或 非本人）） |
| `MaterialReceiptPosting.call` | 新增**可选** `qty:`（缺省仍读整单量，既有调用方不变） |
| `Workflow#create_draft` | 加 D7 阻断（复用 strike 三步序与豁免） |
| `Workflow#apply_complete` | 由「项目负责人直接入库」改为**验收 `passed` 后触发**；原入口按 `can_verify_receipt?` 收口 |
| 新增验收流程服务 | 提交验货 / 通过 / 拒收 |
| `Scinote::ElnUi` 配置 | 新增 `receipt_pending_block_limit`（默认 2），注册进 `DEFAULTS` 与 settings schema |

## 被否掉的方案

| 方案 | 否掉理由 |
| --- | --- |
| 不建表，结论挂申请单 3 列 | 基数 N 下挂列无处安放、照片无法分批归属。用户已选「可分批」 |
| 验货人沿用终审名单（ADR-0030 现行） | 用户要求「验货人员可配置」。**这是本 ADR 修正 ADR-0030 的唯一实质点** |
| 另建一套「未验货阻断」逻辑与豁免表 | 用户明令「跟测试服务未及时上传结果采用相同的处理」——**机制只能一份** |
| 阈值做 per-project 表 | 与 strike 的模块级配置不一致 = 第三套口径。**用户已裁定** |
| 阻断挂在「提交」而非「创建」 | 与 strike 同位置才叫「相同处理」；且建草稿即占队列，卡在创建更早 |
| 自审策略用「名单隐含」 | 名单是「谁能验」，策略是「能不能验自己」——**两个问题**，用户选了独立开关 |
| 验货不通过 → 新增「验收不合格」状态 | 用户选「退回 submitted 重走审批」，不新增状态 |

## 代价与风险（明写）

1. **中间态停留时间必然变长**（分批 ⇒ 「已验 1 批还有 2 批没到」是常态）。D7 阻断与待办催办必须配套。
2. **D4 判拒收 ⇒ 终审做两次**。用户已接受；这是 ADR-0030 备选 C「宁可多一道人工确认、不要账实静默漂移」
   在验货环节的同一取舍。
3. **材料申请也会被冻结**（镜像的另一面）。管理员只有一张 `ServiceStrikeWaiver` 豁免可用 ——
   若同时被服务 strike 与未验货阻断卡住，**一次豁免只能放行其中一处**，这是复用带来的真实约束，
   实现时须在报错里说清「放行的是哪一项」。
4. **`MaterialReceiptPosting` 多了一个能写错数的入口**（可选 `qty:`）。「不传」与「传」两条路径都要有测试。
5. **首次在 addon model 上用宿主 ActiveStorage**，需确认生产 blob 落盘与附件权限/清理相容。
6. ⚠ **会与既有护栏打架**：`_verify_res_center.js` 的 E4 段（真机新建申请草稿）用的是 **hpxing**；
   一旦 hpxing 名下 `project_approved` 且未验货的申请数 ≥ 2，**E4 会被新闸门拦住而变红**。
   实现时须同步处理（例如把 seed 里 hpxing 的未验货单数控在阈值下），否则是「新功能正确、旧护栏误报」。

## 待实现时须核对的点（本轮未验证）

- ActiveStorage 在生产容器的配置与落盘路径。
- 「累计已验 ≥ 申请量即 completed」在**申请量被改**（草稿期可改）后是否与已验量错位。
- D7 计数口径：同一申请人在同项目内 `project_approved` 且累计已验 < 申请量的**申请数**（非批次数）。
