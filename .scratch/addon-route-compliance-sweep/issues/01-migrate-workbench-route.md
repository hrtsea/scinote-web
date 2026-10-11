# 01: 迁移 workbench 路由到引擎自注册

**What to build:** 让 `/eln_workbench` 这条路由由 workbench addon 自己声明、自己注册，而不是寄生在宿主的 `config/routes.rb` 里。迁移前后这个 URL 和它的 helper 名逐字不变——使用者与前端完全无感。做完之后，"注释 Gemfile 一行即可优雅禁用"这条契约保证才对 workbench 真正成立。

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] 新增 addon 自己的路由定义文件，含那 1 条路由，控制器名不写命名空间前缀
- [x] engine 增加 routes initializer，显式 `after: :add_routes`，以 append 方式挂载到根路径
- [x] 迁移前后「动词 + 路径 + helper 名 + controller#action」四项全等，数量为 1
- [x] `/eln_workbench` 迁移前后都返回 HTTP 200（迁移前先取基线，迁移后对拍）
- [x] helper 名 `eln_workbench` 逐字保留，宿主侧仍可调用
- [x] 宿主 `config/routes.rb` 中该路由及其说明注释已删除，残留 grep 为 0
- [x] 删除的行数与该路由块的实际区间相符（防止误删相邻内容）
- [x] 宿主文件改后 Ruby 语法检查通过
- [x] 前端零改动：未触碰任何 Vue 源码或 webpack entry

## 补充说明

- 控制器名**不能**带 `scinote/workbench/` 前缀——engine 声明了 `isolate_namespace`，其 route set 自带该前缀，路由里再写全会解析成双层前缀，导致路由匹配得上但 recognition 报 missing controller（500）。这一点 access_control 的路由文件里有实测记录可参照。
- **不要写 helper 转发**：workbench 只有 1 条页面入口路由，宿主侧没有任何地方调它的具名 helper。若实施时发现确有调用点，才补转发，且必须用 `method_missing` 惰性转发（ELN UI 实测：任何"启动期把方法塞进某模块"的写法都会与 Rails 路由初始化时序赛跑而失败）。
- 若实施时发现宿主侧确有调用 helper 的地方，停下来记录，不要自行扩大范围。
## 实施记录

- 迁移前先查前端是否硬编码 `/eln_workbench`：`app/javascript` 与 `app/views` **零引用**
  （注释里提到的 `router_link_host.js` 已不存在），故迁移对前端无影响。
- 新增 `addons/workbench/config/routes.rb`（该addon 原本**连 config 目录都没有**），
  控制器名写 `workbench#index`（不带 `scinote/workbench/` 前缀）。
- engine 加 routes initializer（`after: :add_routes` + `app.routes.append` +挂根）。
- 宿主删除 8 行块 + 1 空行 = 9 行，与预期区间相符；残留 grep = 0；`ruby -c` 通过。
- 真机：`/eln_workbench` 200，且项目详情/列表/资源中心均200（零回归）。
- **不需要 helper 转发**：宿主侧无任何地方调 `eln_workbench_*_path`（视图只引 assets）。
