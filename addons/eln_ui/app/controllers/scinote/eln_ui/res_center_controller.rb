# frozen_string_literal: true

# ELN UI —— 资源中心页（按 Vue3 原型 ELN系统-Vue3/src/views/ResCenter.vue 重建）
#
# 形状与既有 controller 一致：宿主 layout 提供侧栏/顶栏；
# 内容区只留挂载点 #eln-res-center，交给 ELN系统-Vue3/src/entries/res_center.js 接管；
# 数据由 ResCenterPayload 从真库取出，以 JSON 块注入，没有第二个数据源。
#
# 与其他页不同的两点：
#   1. 资源中心是**跨项目**视图（不是按单个 project 加载），所以没有 set_project；
#      权限检查也宽到「当前 team 下任一 Repository / Project 可读」即可。
#   2. 5 个 tab 用同一条 payload：inventory + ledger + consume 走原生 Repository 体系；
#      apply + cost 走 addon 自有表。服务层一处取齐，前端一次拿完，
#      切 tab 不再打服务端。
module Scinote
  module ElnUi
    class ResCenterController < ApplicationController
      before_action :require_login
      before_action :check_team_membership

      def index
        @payload_json = JSON.generate(payload).gsub('<', '\\u003c')
      end

      # 报告 §5 第 6 项 #12：消耗/执行明细导出（与 consume 页签同源筛选）。
      # 筛选条件走 query（type/project_id/user_id/range_from/range_to），导出 CSV。
      def export
        filters = params.permit(:type, :project_id, :user_id, :range_from, :range_to).to_h
        records = Scinote::ElnUi::ResCenterPayload.filtered_consume_records(
          user: current_user, team: current_team, filters: filters
        )
        csv = Scinote::ElnUi::ConsumeCsvExport.generate(records)
        send_data csv, filename: "consume-export-#{Date.today}.csv",
                  type: 'text/csv; charset=utf-8', disposition: 'attachment'
      end

      # 资源中心 4+1 张表（出入库 / 消耗 / 按项目 / 按成员 / 申请单）的服务端网格端点。
      # 与宿主 shared/datatable/table.vue 契约对齐：{ data:[{id,type,attributes}], meta:{...} }。
      # 复用在 ResCenterPayload 同一套取数/聚合，从构造上守单真源。
      def grid
        dataset = params[:dataset].to_s
        filters = {
          type: params[:type],
          project: params[:project],
          project_id: params[:project_id],
          user: params[:user],
          user_id: params[:user_id],
          submitter_id: params[:submitter_id],
          status: params[:status],
          kind: params[:kind],
          range_from: params[:range_from],
          range_to: params[:range_to]
        }.delete_if { |_k, v| v.nil? || v == '' }
        order = normalize_order(params[:order])
        page = params[:page].presence || 1
        per_page = params[:per_page].presence || 20
        result = Scinote::ElnUi::ResCenterPayload.new(
          user: current_user, team: current_team, filters: filters.with_indifferent_access
        ).grid_rows(dataset: dataset, filters: filters, order: order, page: page, per_page: per_page)
        render json: result
      end

      def normalize_order(order)
        return nil if order.blank?

        order.is_a?(Array) ? order : [order]
      end

      private

      def require_login
        return if current_user

        redirect_to '/login'
      end

      def check_team_membership
        return if current_team

        render_403 and return
      end

      def payload
        base = Scinote::ElnUi::ResCenterPayload.call(
          user: current_user,
          team: current_team
        )
        native = native_repository_props
        base[:inventory] = (base[:inventory] || {}).merge(native: native) if native
        base
      end

      # 资源台账页签要渲染的**宿主原生组件**（app/javascript/vue/repositories/table.vue，
      # 也就是 /repositories 那张原生库存表）所需的 URL / 状态。
      #
      # 2026-10-09 换承载之前，这些 URL 是 ERB 直接写在 <repositories-table> 属性上的；
      # 现在组件由 ResCenter 自己的 Vue app 渲染，属性只能从 payload 来 —— 但它们
      # **必须继续在服务端生成**：
      #   · repositories_path / actions_toolbar_team_repositories_path 是路由助手 ——
      #     ⚠ 必须经 host_routes 全限定调，裸调整页 500（见下）；
      #   · can_create_repositories? 是 Canaid 的权限判定（PermissionsHelper 经 railtie
      #     注入 ActionController，靠 current_user 解析）——前端无从得知，不许自己拼。
      #     （2026-10-09 探针实证：addon controller 上可直呼，且与 app/permissions/team.rb
      #      的判定本体 `team.permission_granted?(user, TeamPermissions::INVENTORIES_CREATE)
      #      && Repository.within_*_limits?` 结果一致 —— 单一真源，别在这里重写一份。）
      # 与原生 ERB 的唯一差异：补上了 userRolesUrl（原生那边漏传了这个 required prop）。
      def native_repository_props
        return nil unless current_team

        {
          dataSource: host_routes.repositories_path(format: :json),
          actionsUrl: host_routes.actions_toolbar_team_repositories_path(current_team),
          createUrl: (can_create_repositories?(current_team) ? host_routes.repositories_path : nil),
          activePageUrl: host_routes.repositories_path,
          archivedPageUrl: host_routes.repositories_path(view_mode: :archived),
          currentViewMode: (params[:view_mode].presence || 'active'),
          userRolesUrl: host_routes.user_roles_repositories_path
        }
      end

      # 🔴 宿主路由助手必须经这里全限定调用。
      #
      # 根因（2026-10-09 探针实证）：addon 是 `isolate_namespace Scinote::ElnUi` 的 engine，
      #   Rails 会把该命名空间下 controller 的 `_routes` 指向**引擎自己的路由集**：
      #     CTRL_ROUTES_IS_ENGINE=true / ENGINE_ROUTE_COUNT=0（引擎没有 config/routes.rb）
      #   于是 controller 里裸调 `repositories_path(format: :json)` 实际走的是
      #     engine.routes.generate(controller: "repositories", action: "index", format: :json)
      #   ⇒ `ActionController::UrlGenerationError (No route matches {controller: "repositories",
      #      action: "index", format: :json})` ⇒ 整页 500。
      #   同一句在 rails runner / 宿主 controller（如 RepositoriesController 的 ERB）里完全正常 ——
      #   差异在 **route set**，不是 project_list_controller.rb:363 当时记的「_recall 参与 url_for」。
      #
      # 与 project_list_controller / notifications_payload / project_list_payload 同一套铁律：
      # addon 里凡引用宿主路由，一律 `Rails.application.routes.url_helpers.<helper>`。
      def host_routes
        ::Rails.application.routes.url_helpers
      end
    end
  end
end
