# frozen_string_literal: true
#
# ELN UI —— addon 自己的路由定义（ADR-0022：宿主 config/routes.rb 零 addon 路由）
#
# 本文件由`script/tools/` 的一次性机械迁移生成，逐条对照宿主原路由搬入，
# **对外 URL 与具名 helper 名逐字不变**（spec 第一验收标准）。
# 守卫：test/eln_ui_route_baseline_test.rb 冻结了迁移前后的 30 条三元组，
# 任何新增/缺失/改名都会让它变红。
#
# ---- 两条踩过的坑（access_control 侧先踩，勿再踩）----
#
# 1. **控制器名不能带命名空间前缀**。本引擎声明了 `isolate_namespace Scinote::ElnUi`，
#    其 route set 自带 `scinote/eln_ui/` 前缀。路由里再写全名会解析成
#    `scinote/eln_ui/scinote/eln_ui/xxx`，而 Zeitwerk 里没有那个类 ⇒
#    路由**匹配得上**但 recognition 报 "references missing controller" ⇒ 500。
#
# 2. **路径不能带前导斜杠**。Rails 7.2 的 `Mapper#translate_controller` 只放行
#    /\A[a-z_0-9][a-z_0-9\/]*\z/，前导 '/' 直接抛 "is not a supported controller name"。
#
# 挂载点为根（engine.rb 的 `app.routes.append { mount ... => '/' }`），因此这里的
# 路径必须写**完整对外路径**（含 /projects/... 等前缀），挂到根后对外 URL 才与迁移前一致。
#
# ⚠ `append` 而非 `prepend`：addon 路由排在宿主之后，addon 无法用同名路径覆盖核心路由
#   （ADR-0022 的安全取舍）。代价是 addon 路由优先级最低——新增路由必须校验不与既有冲突。

Scinote::ElnUi::Engine.routes.draw do
  # GET
  get 'projects/:project_id/eln_project_detail',
      to: 'project_detail#show',
      as: :project_eln_detail

  # PATCH
  patch 'projects/:project_id/eln_project_detail',
      to: 'project_detail#update',
      as: :project_eln_detail_update

  # POST
  post 'projects/:project_id/eln_project_detail/status',
      to: 'project_detail#change_status',
      as: :project_eln_detail_status

  # POST
  post 'projects/:project_id/eln_project_detail/task_book',
      to: 'project_detail#upload_task_book',
      as: :project_eln_detail_task_book

  # POST
  post 'projects/:project_id/eln_project_detail/metrics',
      to: 'project_detail#create_metric',
      as: :project_eln_detail_metrics

  # PATCH
  patch 'projects/:project_id/eln_project_detail/metrics/:id',
      to: 'project_detail#update_metric',
      as: :project_eln_detail_metric_update

  # DELETE
  delete 'projects/:project_id/eln_project_detail/metrics/:id',
      to: 'project_detail#destroy_metric',
      as: :project_eln_detail_metric_destroy

  # POST
  post 'projects/:project_id/eln_project_detail/metrics/:id/toggle',
      to: 'project_detail#toggle_metric',
      as: :project_eln_detail_metric_toggle

  # GET
  get 'projects/:project_id/eln_project_detail/export',
      to: 'project_detail#export',
      as: :project_eln_detail_export

  # :get,:post
  match 'projects/:project_id/eln_project_detail/grid',
        to: 'project_detail#grid',
        as: :project_eln_detail_grid,
        via: [:get, :post]

  # GET
  get 'eln_project_list',
      to: 'project_list#index',
      as: :eln_project_list

  # GET
  get 'eln_project_list_v1',
      to: 'project_list#v1',
      as: :eln_project_list_v1

  # GET
  get 'eln_project_list/grid',
      to: 'project_list#grid'

  # POST
  post 'eln_project_list/actions',
      to: 'project_list#actions'

  # GET
  get 'experiments/:id/eln_exp_detail',
      to: 'exp_detail#index',
      as: :eln_exp_detail

  # GET
  get 'experiments/:experiment_id/my_modules/:id/eln_task_detail',
      to: 'my_module_detail#index',
      as: :eln_task_detail

  # GET
  get 'eln_res_center',
      to: 'res_center#index',
      as: :eln_res_center

  # GET
  get 'eln_res_center/export',
      to: 'res_center#export',
      as: :eln_res_center_export

  # :get,:post
  match 'eln_res_center/grid',
        to: 'res_center#grid',
        as: :eln_res_center_grid,
        via: [:get, :post]

  # GET
  get 'eln_res_apply/:no',
      to: 'res_apply_detail#show',
      as: :eln_res_apply_detail

  # POST
  post 'eln_res_apply/:no/actions',
      to: 'res_apply_action#create',
      as: :eln_res_apply_action

  # POST
  post 'eln_res_applications',
      to: 'res_apply_create#create',
      as: :eln_res_applications

  # GET
  get 'eln_project_approvers',
      to: 'project_approvers#index',
      as: :eln_project_approvers

  # POST
  post 'eln_project_approvers',
      to: 'project_approvers#create'

  # POST
  post 'eln_project_approvers/init',
      to: 'project_approvers#init',
      as: :eln_project_approvers_init

  # DELETE
  delete 'eln_project_approvers/:id',
      to: 'project_approvers#destroy',
      as: :eln_project_approver

  # POST
  post 'eln_project_approvers/receipt_policy',
      to: 'project_approvers#update_receipt_policy',
      as: :eln_project_approver_receipt_policy

  # POST
  post 'eln_task_close/:my_module_id/actions',
      to: 'task_close_action#create',
      as: :eln_task_close_action

  # GET
  get 'eln_notifications',
      to: 'notifications#index',
      as: :eln_notifications

  # PATCH
  patch 'eln_notifications/:id/read',
      to: 'notifications#read',
      as: :eln_notification_read

  # GET
  # 工作台（原 workbench addon，2026-10-12 并入 eln_ui —— 见 ADR-0045）。
  # 其前端（Vue Workbench.vue / entry eln_workbench）本就位于 eln_ui 的
  # app/javascript/vue/eln/，webpack 入口也在 config/webpack/webpack.config.js
  # 指向 eln_ui；此路由只补齐后端入口。对外 URL /eln_workbench 与 helper
  # eln_workbench 逐字不变，宿主侧没有任何代码调该 helper（视图只引 assets）。
  get 'eln_workbench',
      to: 'workbench#index',
      as: :eln_workbench

end
