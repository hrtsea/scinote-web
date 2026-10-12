# ADR-0049: 必传文档固定清单化（规范清单补种 + 行级上传，不建归档闸）

## Status
Accepted（2026-10-13 实施完毕并真机验收）

## Context

需求本身被用户推翻过一次：先说「项目负责人可以增删必传文档」，后改「必传文档不需要可配置」
⇒ 需求重排为「把 5 类固定清单在真机上正确呈现」。

重排前，四件事同时为真，互相打脸：

1. `ProjectDetail.vue:176` 写死枚举「立项申请材料、项目任务书、年度计划、年度报告、结题报告为必传」；
2. 真机项目 34 只有 1 行（项目任务书），与文案的 5 类对不上；
3. 项目 36 的 5 行是手工塞的 `_seed_` 前缀种数据（日期与 mock.js 逐字一致）——截图看着齐，库里名字没洗；
4. **归档完整性闸门根本不存在**：`ProjectDetail.vue:298-307` 只是前端警告面板，
   `change_status`（`project_detail_controller.rb:85-102`）唯一守卫是 `can_archive_project?`，
   `project_archive_export.rb:23` 只把必传写进导出行。页面却写着「缺失将阻断归档流程」。

候选方案：

- **A. 前端写死 5 类**（维持原型态文案）：驳回——真机数据与文案漂移正是当前 bug；
  且「已上传」状态没有承载面，写死等于继续演。
- **B. 可配置清单**（分类字典表 + owner CRUD）：用户已撤回；宿主亦无可复用文档分类模型
  （`grep DocTag|doc_tag` 零命中，`Project` grep doc 零命中），自建字典表是纯新增复杂度。
- **C. 固定清单种进 DB + 服务端规范清单补种 + 行级上传**：采纳。

## Decision

1. **规范清单住服务端，展示真源住 DB**：`RequiredDocSeeder::REQUIRED_DOC_NAMES`
   （5 类定序）只作补种定义；页面渲染的永远是 `eln_ui_project_documents` 行。
2. **补种双路**：一次性迁移（洗 `_seed_` + 补缺 + position 归一，覆盖已纳管项目 34/36）
   + `show` 内幂等懒补种（闸门 = `ProjectProfile.exists?`）。
3. **懒补种放 `controller#show` 而非 payload**：payload 是 export / 测试共用的纯读装配器；
   「已纳管」是事后状态（`upsert_for!` 只在 update / update_status 调），无创建钩子可挂。
4. **`docs_block` 补 `:id`**（required / other 两支）：网格行 id = 台账主键，行级操作才有稳定抓手
   （原先 `grid_support.rb:100` 兜底 `row-#{i}`，按行操作必漂）。
5. **上传泛化**：新端点 `POST /projects/:project_id/eln_project_detail/document` 收 `{id, file}`，
   按 `project_id + id + category='required'` 定位（越权 404）；响应全量 payload（与指标 CRUD 同款）；
   旧 `upload_task_book` 路由降级为退役壳（410 + 指向新端点），删 `TASK_BOOK_NAME` 冻结常量。
6. **不建归档闸门**：缺必传文档仍可置已结题 / 导出；前端告警面板保留，文案软化为规范表述
   （「归档前应齐备」），不再声明不存在的机制。

## Consequences

**好处**
- 清单 / 状态 / 文案 / 上传四者同源同层，漂移面从 4 处收窄到 1 处（DB 行）。
- 项目 34 从 1 行变 5 行、告警如实亮红（确实缺 4 份）——是修正不是回归。
- `_seed_` 手工种数据规范化；行 id 稳定后可继续做行级操作（下载 / 预览留了口子）。

**代价**
- 读路径引入写：`show` 多一次 EXISTS，首次 5 次 INSERT（每项目一生一次，可接受）。
- 迁移不可逆（`down` raise），回滚靠手工删行。
- 路由 30→31（`eln_ui_route_baseline_test` 基线同步更新）。
- 归档「阻断」是软文案：没有机制兜底，靠人看告警。

**已知缺口（有意不补，后续如需求变化再立项）**
- 归档闸门缺失：缺必传文档不影响 `archive!` / 导出。
- 「其他文档」上传未接（按钮是占位）；行内「预览 · 下载」未接（占位）。
- 懒补种只挂 `show`：直接打 grid / export URL 的边角流不会补种（真实流不可达）。

## 实施记录（2026-10-13）

- 新增 `RequiredDocSeeder`（5 用例 / 17 assertions，变异测试验 position 归一生效）。
- 迁移 `20261012120000`（洗 `_seed_` + 补缺 + 归一）+ 补丁 `20261012120100`
  （spec §4.3 只写了 required，漏了项目 36 两行 other 的 `_seed_`；D5/G4 决策原文
  不带 category 限定 ⇒ 补丁全量洗白，`SEED_LEFT=0`）。
- `docs_block` 两分支补 `:id`；既有精确哈希断言同票改为 id 归属 + 四字段比对。
- 路由 30→31（基线 fixture 重生成）。🔴 重生成时连修两个暗疾：dump 脚本
  `RouteSet#routes` 返回 `Journey::Routes`（`is_a?(Array)` 恒 false ⇒ 取样恒 0，
  迁移后从未成功重跑过）+ 容器内非 root 写不了 fixtures；守卫 test 同款已修。
- `upload_task_book` 退役壳 410；`TASK_BOOK_NAME` 删除；页头上传按钮移除，
  上传入口挪必传文档表格行内。
- 全量套件 `378 runs / 1F+6E`（失败集与存量基线逐字一致；ResCenter scene_team
  那条 E 为测试间污染 flaky，单跑 35/0/0）。
- Playwright 真机 `24/24 PASS`：P34 五行规范序 / 1/5 / owner 上传结题报告 ⇒ 2/5 /
  日期=容器 UTC 当天 / 归档告警亮红缺 4；P36 无 `_seed_`。0 JS 错误。
  ⚠ 验收踩坑两条：owner 是 `hrtsea@qq.com`（User.first 非 owner，上传按钮不渲染
  是权限正确行为）；`setFiles` 后不能只等 `domcontentloaded`（reload 尚未发生，
  读到旧 DOM），要等页面真正刷到目标态。
