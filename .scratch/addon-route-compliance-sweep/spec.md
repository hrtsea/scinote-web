# Spec — 其余 addon 路由合规收尾（workbench 迁移 + access_control 死代码清理）

> Status: ready-for-agent
> 依据：`docs/development/addon-dev-workflow.md`、`addons-host-contract.md`、`addons-zero-intrusion.md`、`docs/adr/0022-addon-routes-self-registration.md`
> 前序：`.scratch/eln-ui-route-self-registration`（eln_ui 已完成，本篇是同一契约的扫尾）
> 领域词汇：ELN UI / 引擎自注册 / 零入侵 / 优雅禁用 / 死代码（沿用 ADR-0022 与既有 addon 文档词汇）

## 问题陈述

ELN UI 的路由自注册已在 `.scratch/eln-ui-route-self-registration` 完成。借那次机会对**全部 10 个 addon**做了合规体检，结果是违规面比预想小得多，但仍有**两处**残留让"零入侵铁律"在整个仓库层面**无法真正成立**：

1. **workbench 是唯一还在役且真违规的 addon**：它的 1 条路由（`GET /eln_workbench`）寄生在宿主 `config/routes.rb`，自己既没有 `config/routes.rb`，engine 里也没有 routes initializer。这条路由**真实生效**（`/eln_workbench` 返回 200，helper 可用），所以"注释 Gemfile 一行即可优雅禁用"这条契约保证对它**仍然不成立**。
2. **access_control 在宿主文件里留了 4 条死代码**：`project_visibility_matrix` 等 4 条。注释写着"路由挂在这里因为 engine 未被 mount，以后改走 engine mount 时可以搬到 addon/config/routes.rb"——但**那次 mount 早已完成**，addon 自己的 4 条路由已生效。实测：宿主那 4 条的 helper **一个都不可用**（`respond_to?` 全 false）、**一条都不在路由表里**，是真死代码。

对使用者而言，现状的代价是：任何人读宿主 `config/routes.rb` 都会以为 workbench 与 access_control 的路由是宿主代码，将来 rebase 上游时会把它们当成本地改动冲突掉——**而这正是"守住单一改动面"这条铁律存在的全部理由**。

## 解决方案

把 workbench 的 1 条路由按 ELN UI 已验证的方式迁进它自己的 `config/routes.rb` 并由引擎自注册；删除 access_control 在宿主文件里那 4 条死代码。收尾后：**宿主 `config/routes.rb` 对全部 10 个 addon 零残留**，零入侵铁律在仓库层面真正成立。

两项都**不改变任何对外 URL 与 helper 名**——书签、邮件通知里的既有链接继续可用，前端与 payload 一行都不用改。

## 用户故事

1. 作为一个维护 SciNote fork 的开发者，我想要宿主 `config/routes.rb` 里不出现任何 addon 路由，以便 rebase 上游时能一眼分清哪些是本地二开。
2. 作为一个维护者，我想要通过注释 Gemfile 一行来禁用 workbench，以便下线该功能时宿主照常启动，而不是留下指向空控制器的路由。
3. 作为一个维护者，我想要宿主文件里那 4 条 access_control 死路由消失，以便不再有人误以为它们是活的、进而"修"一个根本不存在的问题。
4. 作为一个审查者，我想要 workbench 迁移前后路由集合与 helper 名逐一相等，以便确认只换了注册位置。
5. 作为 workbench 的使用者，我想要 `/eln_workbench` 这个 URL 继续可用，以便既有书签与导航不受影响。
6. 作为 access_control 的使用者，我想要 `/access_permissions/...` 与 `/projects/:id/visibility_*` 两组路由行为完全不变，以便权限页零感知。
7. 作为一个后续要给新 addon 套模板的人，我想要这 10 个 addon 的写法完全一致，以便照抄任何一个都不会抄到违规的那份。
8. 作为一个维护者，我想要这次收尾把每个 addon 的合规状态写进记忆/文档，以便将来新增 addon 时能立刻对照检查，而不是等审阅才发现又漏了一个。

## 实现决策

### workbench 迁移（与 eln_ui 同构，机制不新造）

- 新增 `addons/workbench/config/routes.rb`，在其中用引擎 route set 定义那 1 条路由。
- engine 增加 routes initializer，显式 `after: :add_routes`，以 `append` 方式把引擎挂载到根路径。
- **控制器名剥掉命名空间前缀**：`isolate_namespace Scinote::Workbench` 已自带该前缀，路由里再写全会解析成双层前缀 ⇒ 路由匹配得上但 recognition 报 missing controller ⇒ 500。
- `as: :eln_workbench` 具名名逐字保留。

### 不需要 helper 转发（与 eln_ui 的关键差异）

- ELN UI 需要转发，是因为宿主代码与 payload 用 `Rails.application.routes.url_helpers` 直接调它的具名 helper。
- workbench 只有 1 条路由、且是页面入口（视图里用 `javascript_include_tag`，不产主动作 URL），**宿主侧没有任何地方调 `eln_workbench_*_path`**。
- 实测 `project_insights`（已卸载的范本 addon）同样零转发代码——**没有调用方就不需要转发**，这是干净写法而非缺失。
- 若实施时发现宿主确有调用点，才补转发；届时必须用 `method_missing` 惰性转发（见"已知陷阱"）。

### access_control 死代码清理

- 直接删除宿主 `config/routes.rb` 里那 4 条路由及其说明注释。
- **不动 addon 自己的 4 条**：它们带 `scope path: 'access_permissions'` 前缀，与宿主那 4 条**路径不同**（`/access_permissions/projects/...` vs `/projects/...`），是两组并存的不同 URL，不是双源。
- 保留 addon 侧代码零改动。

### 范围外（明确不做）

- 不动已卸载 addon（i18n / esignatures / project_insights / ai_eln）的任何代码——它们的合规性已在代码里保持。
- 不改任何 addon 的前端资产登记、decorator、permission、migration。
- 不改 access_control 的 helper 转发实现——它当前 `respond_to?` 为 true，是全仓库唯一真 OK 的写法，留作范本。
- 不修 `addon_settings` 的 helper 提升（实测同为 `defined_not_respond`，属既有遗留，另开 spec）。

## 测试决策

好的测试只断言外部行为：路由集合、URL 可达性，不断言文件位置或 initializer 内部写法。

### 必守的回归断言

1. **workbench 路由等价**：迁移前后「动词 + 路径 + helper 名 + controller#action」四项全等，数量为 1。
2. **URL 不变**：`/eln_workbench` 迁移前后都返回 200。
3. **宿主零残留**：宿主 `config/routes.rb` 不含任何 `to: 'scinote/<addon>/`（对全部 10 个 addon 统一断言，而不是只查本次两个）。
4. **access_control 未受影响**：4 条生效路由（`/access_permissions/...` 与 `/projects/:id/visibility_*`）行为与 helper 名不变。
5. **兜底自查**：对其余 8 个 addon 断言"宿主 routes.rb 零残留"这一条恒成立——防止将来新增 addon 时重蹈覆辙。

### 测试先例

- 沿用 ELN UI 建立的基线机制（`test/fixtures/*.json` + minitest 守卫），不新造概念。
- 真机验证沿用既有接缝：容器内 `rails runner` 探针 + 签名会话 curl。
- ⚠ **`RAILS_ENV=test` 与独立 runner 进程里 addon 的 `Engine.routes` 都是 0 条**（routes initializer 只在服务进程启动时执行）⇒ 依赖运行时路由的断言必须由**真机 HTTP + 静态对拍**承担，测试环境只保留静态可判的部分。

## 范围外

- 不引入新的 helper 转发实现（除非实施时发现 workbench 确有调用方）。
- 不做 access_control 的 helper 转发修复（它是唯一 OK 的，作为范本保留）。
- 不修 addon_settings 的 helper 提升失效问题。
- 不动已卸载 addon。
- 不改前端。

## 补充说明

### 已知陷阱（ELN UI 实测，本次直接复用）

- **helper 转发必须用 `method_missing` 惰性转发**：任何"启动期把方法塞进某模块"的写法都会与 Rails 路由初始化时序赛跑而失败（`respond_to?` 恒 false / 被冲掉且回报成功 / 生产只跑一次导致 500）。若本篇需要转发，直接照抄 ELN UI 的做法。
- **迁移脚本不要手抄路由**：ELN UI 那次手抄正则连续踩 3 个坑（跨行 `\s`、吞掉邻接路由、action 名含数字）。workbench 只有 1 条，但仍建议逐字复制原行而不是重新构造。
- **删除宿主路由后必须核验删除行数**与预期块区间相符，防止误删相邻内容（ELN UI 那次曾误删 370 行）。

### 与 ADR 的关系

本规格**执行** ADR-0022 已 Accepted 的统一契约，不新开决策。完成后可在 ADR-0022 补记"全部在役 addon 已完成自注册"，并把 access_control 宿主那条过时注释的处置记入。

### 交付形态

两项改动都**很小**（workbench +1 文件、宿主 -1 块；access_control 宿主 -1 块），可视为同一个提交的两次动作，或拆成两个提交。建议拆开：workbench 是行为迁移（有可达性风险），access_control 是死代码清理（零行为风险），分开便于回溯。