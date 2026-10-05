# 微信 / 企微网关 Addon — 术语表指针

> **本文件的术语表已迁出。** 唯一术语来源是：
>
> ### → [`addons/wechat_gateway/CONTEXT.md`](../../../addons/wechat_gateway/CONTEXT.md)
>
> 术语新增、修订、澄清一律在**那一边**做。本文件保留，仅记录迁移理由与随之修订的三条陈旧术语。

## 为什么迁出

主文件是宿主开发计划的一部分（`docs/开发计划/wechat-gateway/`），而 addon 术语随 addon 代码演进。两者混在一处导致：

1. addon 术语与宿主实体定义挤在同一张表里，边界不清；
2. 术语条目逐渐被实现细节与变更历史污染（不再是一份干净的 glossary）；
3. 术语表的实际读者和使用者都在 `addons/wechat_gateway/` 目录下。

拆分遵循 `docs/agents/domain.md` 的「按功能分目录存放术语表」约定。**ADR 仍统一放在 `docs/adr/`。**

## 随本次迁移修订的术语（原表已过时）

| 原表述 | 事实 | 处理 |
|---|---|---|
| 「网关当前**不新建** Project，仅读取 `WECHAT_GATEWAY_PROJECT_ID` 指定的既有 Project」 | addon 已可新建项目，并在新建后直接作为用户默认项目 | 已删否定表述，改为「Project 是可写实体」 |
| Experiment 由「`Experiments::CreateService`」创建 | 宿主实际为无命名空间的 `CreateExperimentService` | 术语表不再绑定具体 service 名；写 permission 语义为准 |
| 隐含「Project 只来自实例配置」 | 存在**用户级长期默认项目**（按 `scinote_user_id` 存储，跨 iLink / 企微两通道共享），且其优先级高于实例配置 | 新增「默认项目 / 实例默认项目」两个术语 |

（另新增 Team 作用域、指令层、规范名与别名、消息级指定 vs 会话定向、可见性校验等术语，见新表。）

## 相关文档

- 术语表：[`addons/wechat_gateway/CONTEXT.md`](../../../addons/wechat_gateway/CONTEXT.md)
- 指令行为事实清单（非术语）：[`addons/wechat_gateway/docs/指令参考.md`](../../../addons/wechat_gateway/docs/指令参考.md)
- 项目选择流程设计：[`项目选择流程设计.md`](./项目选择流程设计.md)
- ADR：`docs/adr/0023`（总体）、`0024`（任务指派语义）、`0025`（指令权限校验）、`0026`（Team 作用域）、`0027`（无删除指令）
