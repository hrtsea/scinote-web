# 03: 证明优雅禁用恢复并记录 ADR

**What to build:** 让契约承诺了却一直没兑现的那条保证被**机器证明**恢复——注释 Gemfile 里 ELN UI 那一行，宿主照常正常启动、ELN UI 的路径返回 404 而非异常或空控制器崩溃。迁移前这条保证是破的（30 条路由寄生在宿主文件里，注释 Gemfile 后它们会指向不再被加载的控制器）。迁移后必须证明它真的回来了。

同时把这次迁移的决策与踩坑写进 ADR，让将来有人想把路由挂回宿主时能看到当初为什么拒绝。

**Blocked by:** 02 — 整块迁移 30 条路由并保持全绿

**Status:** resolved

- [x] 隔离环境中注释 ELN UI 的 Gemfile 行后，宿主正常启动，无 NameError、无启动崩溃
      → 实测：`sed`注释 + `bundle install --local`(root) + 重启 ⇒ HTTP 200，零崩溃日志
- [x] ELN UI 的路径此时返回 404，而非 500 或路由异常
      → 实测 **7/7 全部 404**（项目详情/列表/资源中心/通知/审批人/孤儿 V1/资源中心网格）
- [x] 恢复 Gemfile 行后一切完全复原（验证过程幂等，不留残留状态）
      → Gemfile md5 三方一致（`6bee1242…`：宿主/容器/备份），7 端点全 200
- [x] 上述禁用/恢复验证接入常跑入口，不会只手工跑一次就失效
      → 新增 `eln_ui_graceful_disable_test.rb`（4 用例，随 run.rb 常跑），静态守住禁用契约的前提；
        真正的禁用实验有副作用不进单测，实测结果记在守卫注释与 ADR-0044。**两路自证均精确变红**。
- [x] 新增 ADR 记录「ELN UI 已完成路由自注册迁移」，并注明所执行的既有 ADR 与所沿用的先例
      → ADR-0044（含 Decision 段声明执行 ADR-0022；沿用 access_control / project_insights 先例）
- [x] 把 access_control 宿主路由处"以后改走 engine mount 时可以搬"的待办注释标记为已验证
      → 该注释已随 4 条死路由**一并删除**（比"标记已办"更彻底）；ADR-0044 专段记录此关系。
- [x] ADR 中记录本域内已踩的坑
      → ADR-0044 §实测确认的两条实现约束已记：helper 必须惰性转发（三种朴素写法各自怎么失败）、
        测试环境运行时路由为空。并更正了"路径不能带前导斜杠"只对控制器名成立。

## 补充说明

- 禁用验证会短暂修改宿主 Gemfile 并重启容器，**必须在隔离环境进行**（临时改动后立即还原），不碰生产容器的持久状态；且须验证还原后的幂等性。
- 这条验证的价值在于恢复契约保证本身，不是"测试覆盖率"。若将来有人再把 addon 路由挂进宿主文件，这条断言会立刻变红。
- 仓库内存在文档互相矛盾，与本 ticket 无关但会误导后来人：一份开发流程文档说 ADR 写入聚合文件，领域文档约定说 ADR 单一存放处是 `docs/adr/`。按后者（更新约定）执行，建议另行修正前者——**不在本 ticket 范围内**。
## 实施记录

### 禁用实验（真实执行，已还原）
1. 备份：宿主与容器 Gemfile md5 均为 `6bee1242…`（记录基线）。
2. `sed` 注释 `gem 'scinote_eln_ui'`（容器侧，root）→ `bundle install --local`（**必须 root**，
   否则写 Gemfile.lock 权限拒绝）→ 重启。
3. **宿主启动成功**（10s，HTTP 200），日志零 NameError / 零崩溃。
4. ELN UI **7 个路径全部 404**（非 500）⇒ 契约保证确已恢复。
5. 还原：解注释 → `bundle install --local` → 重启 → Gemfile md5 与禁用前一致、7 端点全 200 ⇒ **幂等、无残留**。

### 🔴 意外发现：workbench 硬依赖 eln_ui（独立于本次迁移的既有债）
禁用期间 `/eln_workbench` 返回 **500**：`NameError: uninitialized constant Scinote::ElnUi`。
真因：`addons/workbench/app/services/scinote/workbench/workbench_payload.rb` 有**三处真实调用**
指向 eln_ui（其余同文件里的 `ElnUi` 都是注释）：
- L227 `::Scinote::ElnUi::NotificationsPayload.unread_count_for(...)`
- L312 `::Scinote::ElnUi::ProjectListScope.participation(...)`
- L343 `::Scinote::ElnUi::ResourceApplication.for_team(...)`

⇒ **workbench 在役却硬依赖 eln_ui**，违反「停用 addon 前必查三路引用」的第一路（Ruby 命名空间常量）。
不影响"eln_ui 自己能被优雅禁用"这条结论，但意味着**目前不能单独禁用 eln_ui 而保 workbench 可用**。
已记入 ADR-0044 §遗留问题，处置需另开 spec（下沉共享逻辑或让 workbench 自持一份）。

### 守卫自证（两路均精确变红）
- 注入「宿主残留 eln_ui 路由」→ 变红并报出"优雅禁用失效"。
- 注入「Gemfile 行被注释」→ 变红（`refute_nil` 命中"契约的唯一开关"）。
- 还原后回绿；Gemfile md5 未变。

### 全量测试
337 runs / 1F / 7E / 2 skips —— 与基线（333/1F/7E/2skips）**同一批 8 个失败同名**，
runs +4 即新增的优雅禁用守卫，零引入回归。
