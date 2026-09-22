# WeChat → SciNote Gateway Addon — Spec

**Feature slug:** wechat-gateway
**Target:** `addons/wechat_gateway`（Rails Engine，命名空间 `Scinote::WechatGateway`）
**参考计划:** `../wechat_to_elabftw/docs/WECHAT-SCINOTE-PLAN.md`

## Goal
把企微群 / 微信私聊里的实验记录自动落到 SciNote，并以**真实操作人**身份建记录；支持组长派任务给组员。进程内 addon，免逐用户 OAuth token（直接以 `user:` 参数调 SciNote service）。

## Channels
- **iLink bot**：私聊 DM（真机已验证可用）
- **企业微信自建应用**：群聊 + @ + 媒体 + 指派（官方支持，群事件 iLink 不投递）

## Core requirements → addon 模块（F1–F10，详见 plan §3）
- F3/F8 绑定：`wechat_user_bindings` 表 + 应用内一次性绑定码（非 OAuth）
- F4/F5 写入：`intake` + `scinote_service_writer`（`Experiments::CreateService` 等，`created_by`=真实用户），草稿 + `/confirm`
- F6 指派：组长 context 校验 `can_manage_my_module_users?` 后调指派 service
- F9 查询 / F10 设备预约：addon 内直查 / 直建 `EquipmentBooking`

## Non-functional
- 审计链真实（`created_by` 真实人，符合 GLP）
- 绑定码一次性 + 过期 + 绑定生成时 SciNote session 用户（防冒领）
- 通道无关：ilink / wecom 只取身份 + 收消息，下游写入层共用

## Dependencies — `wechat` gem 使用边界（2026-09-10 评估）
- **已引入** `s.add_dependency 'wechat'`（v1.2.0），装于 `F:\ruby_gems`（自定义 GEM_HOME，避 C 盘空间不足）。
- **仅用于出站 `Wechat::CorpApi`**：`message_send`(ticket 07 回包)、`get_material`(媒体下载)、`getuserinfo`/`getuserid`(ticket 02 绑定解析)。该路径 HTTPS+access_token，与回调 AES 无关。
- **不用于回调加解密**：gem 的 `Wechat::Cipher`/`Wechat::Responder` 用非标准 IV（`[key_data].pack('H*')`），与微信规范 `key[0,16]` 不兼容，解不开真实企微回调。回调验签/AES 解密继续用自研 `WecomCrypto`（ticket 04）。
- **iLink**：gem 完全不支持，保留自研 `IlinkCrypto` / `IlinkBridge`（ticket 05）。
