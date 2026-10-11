# frozen_string_literal: true
#
# workbench addon —— 自己的路由定义（ADR-0022：宿主 config/routes.rb 零 addon 路由）
#
# REQ-DASHBOARD / SCN-DASH-1~7：按登录角色渲染首页，只给状态统计，
# 详情一律下钻到对应页面；统计数据全部实时读业务库（无缓存快照）。
#
# ⚠ path 用 /eln_workbench（不是原型的 /workbench）—— 各页面包屑「工作台」
#   的宿主映射在 ELN系统-Vue3 的 router link 改写处，路径不可改。
#
# ---- 为什么控制器名不写命名空间前缀 ----
# 本引擎声明了 `isolate_namespace Scinote::Workbench`，其 route set 自带
# `scinote/workbench/` 前缀。路由里再写全名会解析成
# `scinote/workbench/scinote/workbench/...`，而 Zeitwerk 里没有那个类 ⇒
# 路由**匹配得上**但recognition 报 "references missing controller" ⇒ 500。
# （access_control 的路由文件里有四种写法的实测对照记录，可参照。）
#
# 挂载点为根（engine.rb 的 `app.routes.append { mount ... => '/' }`），
# 所以这里写完整对外路径 `/eln_workbench`，挂到根后对外 URL 与迁移前逐字一致。

Scinote::Workbench::Engine.routes.draw do
  get 'eln_workbench',
      to: 'workbench#index',
      as: :eln_workbench
end