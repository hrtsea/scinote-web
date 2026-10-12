# ADR-0050: 项目文档附件读取链路与 other 上传接线（显式端点 + 可读权限 + 行内 URL）

## Status
Accepted（2026-10-13，实施完成；含宿主白名单扩展，见实施记录）

## Context

ADR-0049 把「必传文档 5 类固定清单」收拢到台账真源后，项目详情页「项目文档」面板仍有两处占位：

1. 「其他文档」subhead 的上传按钮是死按钮（无 `@click`），other 表格只有占位「下载」
2. 两张表的「预览 · 下载」是文字占位，无 handler

补这两条需要先定四个决策，每个都有真实替代方案：

- **链路形态**：payload 直接下发 ActiveStorage signed URL（零新路由）vs 新端点 redirect（宿主 controller 先例）
- **权限档位**：owner/组长才能下载 vs 可读者即可
- **创建入口**：other 表行内上传 vs subhead 按钮建新行
- **URL 下发**：行数据自包含 vs actions 模板替换

## Decision

1. **预览/下载走显式端点**：`GET .../documents/:id/preview|download`，controller
   `redirect_to rails_blob_path(doc.file, disposition: 'inline'|'attachment')`。
   不把 signed_id 下发到 payload/grid JSON——signed_id 是**永久有效的下载凭证**，
   塞进页面 HTML 等于任何能看源码的人（爬虫、分享屏幕、日志采集）都拿到直链；
   显式端点让权限在 controller 显式校验，URL 稳定可审计。
   宿主 7 处先例（`assets_controller.rb:190` 等）全是这个范式，addon 跟随不另立。
2. **权限 = 可读者**：新端点挂既有 `check_project_read_permissions` before_action，
   不写新权限代码。依据：面板本已向可读者展示文件名/上传人/日期，附件不额外设限才自洽
   （宿主原生附件下载也只校验可读）。后果显式接受：项目所有成员可下载全部附件。
3. **other 上传 = subhead 按钮建新行**：other 是「过程记录、参考资料等，随时上传归档」的
   累积语义（subhead 原文案），与 required 的预置 5 类行不同构；空项目 34 的 other 表为空，
   行内入口第一个文件永远传不上去。已有行**不做替换**（Q5=A）——「某日交了什么」的过程
   痕迹比「最新版」更重要，传错再传一条。
4. **行内 URL 下发**：`docs_block` 每行带 `previewUrl/downloadUrl`（仅 `file.attached?`），
   grid attributes 同源摊平。遵守 payload 既有铁律「URL 一律由宿主 named route 生成，
   前端不许拼宿主路径」（`projectBasic` 本来就没有 id 字段，前端想拼也拼不出）。

## Consequences

**变得容易**：
- other 表格从纯展示变成可增长台账；两张表附件可读，占位清零
- 下载/预览 URL 不带签名，payload 可安全进 HTML/日志
- 新端点零新增权限代码（读权限整页已守）

**变得困难/付出代价**：
- 路由 31→33，基线 fixture 重生成 + 容器重启（helper 转发从 JSON 读的既有坑）
- `docs_block` 每行多两个键（nil 不加键）；`actions_block` 多 `createDocument`，
  actions_test 的 URL 断言要同步
- 下载按钮走 handler + `window.location.assign`（renderer 的 href 分支强制新标签，
  下载会留空标签）——renderer 不动，为下载造 href 变体不值

**已知缺口（有意不补）**：
- other 行无「替换文件」（过程痕迹优先）
- 预览不弹模态（iframe 有 X-Frame-Options 风险 + 宿主零先例）；docx/xlsx 浏览器自行下载
- other 行无删除入口（台账无删除语义）
- 预览/下载无审计日志（宿主附件系统也没有，对齐现状不先造）

## 实施记录（2026-10-13）

**交付**：路由 31→34（create_document / preview_document / download_document）；payload
`docs_block` 两分支行内 `previewUrl/downloadUrl`（仅 attached，私有 `route_helpers` 收口）；
前端 other 上传按钮接线（`pickDocFile({create:true})` 分流 create/覆盖端点）、两表
「预览/下载」拆两个（href 分支新标签 + handler location.assign）、列宽 200/170。

**验证**：单测新增 `eln_ui_project_detail_doc_actions_test` 9 例全绿 + 变异 3/3
（create 权限守门 / project_id 域 / attached 守门）；detail/grid/actions 三类同步；
全量 387 runs / 1F+6E（存量集逐字一致）；Playwright `e2e_eln_doc_actions.js` **24/24**
（other 上传全自动元数据 / 预览全链 200 docx / 下载 200 attachment 文件名 / 非 owner
双向 / 已上传⇔有按钮动态断言）。

**规格外发现与处置（都进了记忆）**：

1. 🔴 **宿主给 ActiveStorage RedirectController 挂了权限关**
   （`app/controllers/active_storage/blobs/redirect_controller.rb` +
   `concerns/active_storage/check_blob_permissions.rb`）：blob 直链也要过
   `check_read_permissions`，其 `case attachment.record_type` 白名单**不认识
   `Scinote::ElnUi::ProjectDocument`** ⇒ else false ⇒ 预览/下载 302 后第二跳
   403 FORBIDDEN。处置 = 在白名单加 when 分支（与 Report 分支同构：
   `can_read_project?(record.project)`）——白名单 case 就是宿主为「新附件持有模型」
   设计的扩展点，加分支是**使用扩展点**而非破坏机制。副作用是双保险：我们的端点管
   「谁能发起」，宿主这一管「URL 可验证」，signed_id 外溢也会被再查一次。
2. 🔴 **controller 实例裸 `rails_blob_path` 踩 _recall**：当前请求的 project_id/id
   混进 url_for ⇒ UrlGenerationError。必须 `::Rails.application.routes.url_helpers.`
   全限定（与 project_list_controller 注释同款坑，ADR-0049 时代已踩过一次）。
3. ⚠ **Rails 7.2 的 disposition 是 query 参数**（`?disposition=inline`）不是路径段
   `(.:disposition)`——测试断言按路径段写会恒假。
4. ⚠ **e2e popup URL 断言 flaky**：Edge 对 inline 不可渲染类型（docx）转下载并关标签，
   popup.url() 时而是空。改为页面内 `fetch(redirect:'follow')` 验全链
   （302→宿主权限关→200 + content-type），零 flaky 且更强。
5. ⚠ **Warden 零口令 cookie 会失效**（非必重启）：owner 会话中途「session expired」，
   重签即可。e2e 前先 curl 探活。
6. ⚠ **AG Grid 空态不渲染网格**：other 表空时 docs pane 只有 1 个 `.ag-theme-alpine`，
   等「第二个网格出现」要用纯 DOM 条件（reload 后注入的 window helper 会丢）。

