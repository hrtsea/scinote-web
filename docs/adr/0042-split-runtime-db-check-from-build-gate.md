# ADR-0042: 构建期 CI 门禁与运行期 DB 依赖的解耦

## Status

Accepted（2026-10-10）

## Context

合并官方 1.50.2 之后首次重建生产镜像，在第 12/16 步 `bin/rails zeitwerk:check` 失败：

```
ActiveRecord::ConnectionNotEstablished: fe_sendauth: no password supplied
```

调用链：

```
bin/rails zeitwerk:check → Rails 初始化
  → config.to_prepare (addons/access_control/lib/scinote/access_control/engine.rb:66)
    → Scinote::AccessControl.verify!  (access_control.rb:42)
      → conn.table_exists?(...)
```

三个事实叠在一起才构成这个冲突：

1. **门禁是我们自加的**（提交 `98e728efd`，注释是中文「CI 门禁」，官方不会有）。它写在 `660c5518b`（ADR-0033 引入 `verify!`）**之前**，当时的假设是「构建期纯静态检查，不需要 DB」。
2. **`verify!` 上线后这个假设失效**。它做两件事，其中表存在性检查必须连库。
3. **构建期那条 `DATABASE_URL=postgresql://postgres@db/scinote_production` 是占位符**，不是真连接。buildkit 里 `db` 解析到 `172.18.0.2`（真实容器网段的 db 地址），但构建期那里没有 db 容器，而且没带密码 ⇒ `fe_sendauth: no password supplied`。

也就是说：**一道为「发现命名错误」设计的静态门禁，被一个运行期一致性检查污染了**。它的两半外部依赖不同，却写成了同一次调用。

同一批重建里还踩了另一个独立的坑：`Gemfile.lock` 里 git 源 gem `odf-report` 的 revision 在官方 merge 后变了（`0c62b60c` → `e1abe7b9`），而本机 `vendor/git-mirror` 浅镜像停在旧 ref，`bundle install --local` 报 `not our ref`。两者性质不同（一个是**可达性锚点**，一个是**运行期依赖**），但共同点是同一个错误类别：

> **构建期门禁对运行期环境做了假设，而这个假设在merge 官方代码后失效了 —— 但失效是静默的，只在 buildkit 里才暴露。**

## Decision

**把 `verify!` 按外部依赖拆成两半，只让构建期跳过需要 DB 的那一半。**

```ruby
def verify!
  verify_tables! unless ENV['SKIP_ACCESS_CONTROL_DB_CHECK'].present?
  # 装饰器探测：纯内存，任何时候都跑
  return if Experiment.method_defined?(:ac_manually_granted?) || ...
  raise 'visibility grant decorator did not load'
end
```

`Dockerfile.production` 第 12 步带上 `SKIP_ACCESS_CONTROL_DB_CHECK=1`，并注释写明「该 ENV 不写进最终镜像」。

### 为什么不给整个 `verify!` 加跳过开关

这是本决策的关键分界。如果图省事在 `verify!` 开头写 `return if ENV[...]`，后果是：

|方案 | 构建期门禁还剩什么 | 代价 |
|---|---|---|
| **跳过整个 `verify!`**（最初提案） | **什么都不剩** | 门禁只剩个名字。ADR-0033 的护栏在 CI 里静默失效，而 CI 是唯一能在 30s 内抓住命名错误的地方 —— 省下 20 分钟，赔上 30 秒门禁的全部价值 |
| **只跳过 `verify_tables!`（采纳）** | 装饰器挂载探测照跑 | 表存在性不在构建期校验（**这是我们要接受的真实损失**，见 Consequences） |

装饰器探测是纯内存的（`Experiment.method_defined?`），不碰数据库。而「装饰器有没有挂上」恰恰是 `verify!` 里更静态、更该在 CI 里抓的那一半 —— `access_control` 是承重件（`self_only_researcher` + UGA 141 条 = 隔离引擎），装饰器掉了就是**隔离静默溶解**，必须在构建期就红。

### 备选项与否决理由

- **构建期起临时 postgres（改 Dockerfile 加 service）**：门禁强度最高（表也在构建期验）。否决原因：`docker build` 里起 db 需要 `network: host` 之类的 hack，脆弱且慢；而且构建期建的空库**验不出生产库的实际状态**（生产库是「照 `_db/migrate_addon.rb` 手工 load」的，见 `verify_tables!` 的错误提示），验了也是假绿。
- **删掉这道 zeitwerk 门**：零成本。否决：命名错误会推迟到 20 分钟后的 webpack 甚至运行时才暴露，定位成本高一个量级。这道门本身设计是对的，要改的是它的**外部依赖假设**，不是它的存在。
- **改 `verify!` 让它容错（`table_exists?` 失败当通过）**：否决 —— 那会让**运行期**也失去这道护栏，而运行期是有真库的，正是它该生效的地方。为了构建期的假连接去削弱真连接的保护，是本末倒置。

## Consequences

**变容易的**：
- `Dockerfile.production` 的 CI 门禁恢复原意：30s 内抓常量命名错，不依赖数据库。
- 以后 merge 官方代码若再引入新的运行期 DB 依赖（类似 `verify!` 这种 `to_prepare` 探测），不会再撞同一堵墙 —— 因为门禁这侧已经声明了「不碰 DB」这个契约。
- `verify_tables!` 拆成独立私有方法后，将来若要**手动跑一次完整校验**（比如运维在生产库上自查），可以只调它，语义清晰。

**变难的（接受的真实损失）**：
- ⚠ **表存在性不再在构建期校验**。如果某个 commit 删了 `access_control_project_strategies` 的迁移，构建镜像时不会报错，要等到**运行时 `to_prepare` 才炸**。补偿手段：错误消息本身指明了修复动作（跑哪个迁移），且运行期启动即炸，不会静默带病上线。
- ⚠ 这个 ENV 是**生产代码里的一个后门开关**。风险控制：默认值是「不跳过」，即默认严格；只有显式传 ENV 才跳过。若某条启动脚本误传了这个 ENV，构建期门禁会失效 —— 因此在 Dockerfile 里用 `RUN` 前置环境变量形式（不写 `ENV`），确保它**只作用于那一条命令，不进入镜像层**。

**可逆性**：高。改法是删三行代码 + 删一行 Dockerfile，`git revert` 或直接手改皆可，无数据迁移、无 schema 变更。

## 护栏自证（按项目铁律：上线前必须验证它真的会红）

| 场景 | 期望 | 实测 |
|---|---|---|
| 正常代码 + 跳过 ENV | 通过 | `Otherwise, all is good!` rc=0 |
| **装饰器方法被改坏** + 跳过 ENV | **红** + 报`decorator did not load` | rc=**1**，报 `visibility grant decorator did not load — check app/decorators/scinote/access_control/*.` |
| 还原后复检 | 通过 | `Otherwise, all is good!` rc=0 |

第二条是关键：它证明**「跳过」只作用于 DB 那半，静态那半没有跟着被废掉**。若当时只跑正常路径（rc=0 就收工），这个护栏可能已经是个空壳而无人知晓。

## 备注：同批的另一个坑（不属于本 ADR 范围）

`Gemfile.lock` 的 git 源 ref 拉不到（`not our ref e1abe7b9`）是**另一个问题**，修法是更新本机 `vendor/git-mirror` 浅镜像（`git fetch --depth 1 origin rich-text-improvements`），`Gemfile.lock` 一个字都不用改。它不属于「构建期 vs 运行期」的解耦范畴，但归类上同属「merge 官方代码后构建期假设失效」这一族，值得记住这个模式。

其中一个方法论教训写在这里：**我曾只看 `Gemfile.lock` 的文本 diff（只差 `revision` 一行）就断言「纯元数据、不需 bundle install」—— 错**。git 源的 revision 是**可达性锚点**，必须 `git fetch` / `git cat-file -t` 验证可达后才能下结论。**文本 diff ≠ 可达性**，这是本项目 git 源依赖特有的陷阱（`Dockerfile.production:54` 用 `insteadOf` 把 git 源重写到本机预克隆，容器内不联网）。
