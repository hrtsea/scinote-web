# 02: 清理 access_control 在宿主文件里的 4 条死路由

**What to build:** 把宿主 `config/routes.rb` 里 access_control 那 4 条早已失效的路由删掉——它们 helper 一个都不可用、也不在路由表里，是纯死代码。删完后宿主文件对 access_control 零残留，避免后来者误以为它们是活的、去"修"一个根本不存在的问题。

**Blocked by:** None (can start immediately)（与 01 无依赖，可独立推进）

**Status:** resolved

- [x] 删除前已确认这 4 条是死的：helper 全不可用 + 一条都不在路由表里（证据已在 spec）
- [x] 宿主文件中该 4 条路由及其说明注释已删除，残留 grep 为 0
- [x] addon 自己的 4 条路由**零改动**（它们带 `access_permissions` 前缀，与宿主那 4 条路径不同，不是双源）
- [x] 4 条生效路由的 helper 名与生成路径完全不变
- [x] `/projects/326/visibility_matrix` 与 `/access_permissions/projects/326/visibility_matrix` 两组 URL 行为不变
- [x] 宿主文件改后 Ruby 语法检查通过

## 补充说明

- 🔴 **这不是双源，删错了会出事**：addon 那 4 条带 `scope path: 'access_permissions'` 前缀
  （`/access_permissions/projects/...`），宿主那 4 条不带前缀（`/projects/...`），
  两组是**并存的不同 URL**，各有各的调用方。本次只删宿主那组。
- 那条过时注释（"路由挂在这里因为 engine 未被 mount，以后改走 engine mount 时可以搬到 addon"）
  本身也是错的——mount 早已完成、addon 路由早已生效，所以注释与现实相反。删除路由时应一并删掉，
  否则会继续误导。
- 零行为风险（死代码），但仍需验证语法与那 4 条生效路由不受影响。
## 实施记录

- 删除前已三重取证：①4 个 helper `respond_to?` **全false**；②一条都不在路由表里
  （`HOST_TABLE_HITS` 只有 addon 那4 条）；③全仓检索 **零处**引用无前缀 helper 名
  （7 处引用全是 `access_permissions_` 前缀版）。
- 删除 17 行块（含说明注释），残留 grep = 0；`ruby -c` 通过。
- 真机确认分组正确：`/access_permissions/projects/326/visibility_matrix` → **200**（addon 版），
  `/projects/326/visibility_matrix` → **404**（宿主版，确实不存在）。
  ⇒ 宿主那 4 条删除**零行为影响**。
- 🔴 **实证：那 4 条带前导斜杠的写法在 Rails 7.2 下根本无法被加载**——
  实测注入 `to: '/scinote/workbench/a#b'` 后，Rails 在加载 routes.rb 时就抛
  `ArgumentError: '/scinote/workbench/a' is not a supported controller name`，
  测试进程根本起不来。这解释了它们为何是死代码（应是旧 Rails 时代写法）。
