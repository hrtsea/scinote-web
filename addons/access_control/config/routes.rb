# frozen_string_literal: true

# D9.4 —— 项目可见性矩阵（成员 × 实验）路由 —— **引擎内版本，当前生效**。
#
# ADR-0022：addon 路由由 engine initializer 自注册，宿主 config/routes.rb 零 addon 路由。
# 这 4 条的对外 URL 与 helper 名跟当初挂在宿主时**逐字一致**
# （宿主 app/views/experiments/index/_header.html.erb:23 直接调老名字），
# 已用 ApplicationController.render 真渲染验证过。
#
# ---- 路径设计 ----
#
# 路径沿用宿主原来那一版的形状（含 /access_permissions/ 前缀）而不是另起根前缀：
# 矩阵页是从「项目 → 访问权限」这条既有入口进去的，挂载点是 addon 的本地决策
# （ADR-0022 §2 说统一的是机制、不是路径）。
#
# ⚠ 这里**不能**用 `namespace :access_permissions`。
#   isolate_namespace Scinote::AccessControl 之后，engine 的 route set 自带
#   `scinote/access_control` 这段 controller 前缀，namespace 又会上加一层：
#     namespace :access_permissions + 'visibility_matrix#show'
#       → scinote/access_control/access_permissions/visibility_matrix
#     而 Zeitwerk 里只有 Scinote::AccessControl::VisibilityMatrixController
#     （文件 app/controllers/scinote/access_control/visibility_matrix_controller.rb）。
#     结果就是路由**匹配得上**、recognition 报 "references missing controller" 500。
#   实测四种写法的解析结果（在容器里 rs.draw 逐条试出来的）：
#     namespace + 'visibility_matrix'        → scinote/access_control/access_permissions/visibility_matrix ✗
#     namespace + '/visibility_matrix'       → visibility_matrix  ✗（丢了引擎前缀）
#     scope(path:) + 'visibility_matrix'     → scinote/access_control/visibility_matrix ✓
#   所以这里只取「URL 前缀」，用 scope 拿路径、用 as: 把老 helper 名原样保住
#   （宿主 app/views/experiments/index/_header.html.erb 直接调的就是这几个名字）。
Scinote::AccessControl::Engine.routes.draw do
  scope path: 'access_permissions' do
    get 'projects/:project_id/visibility_matrix',
        to: 'visibility_matrix#show', as: :access_permissions_project_visibility_matrix
    post 'projects/:project_id/visibility_matrix/:user_id/:experiment_id',
         to: 'visibility_matrix#toggle', as: :access_permissions_toggle_project_visibility_matrix
    patch 'projects/:project_id/visibility_strategy',
          to: 'visibility_matrix#update_strategy', as: :access_permissions_project_visibility_strategy
    post 'projects/:project_id/visibility_backfill',
         to: 'visibility_matrix#backfill', as: :access_permissions_project_visibility_backfill
  end
end
