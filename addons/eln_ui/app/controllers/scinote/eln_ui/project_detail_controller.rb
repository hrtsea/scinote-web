# frozen_string_literal: true

# ELN UI —— 项目详情页（按 Vue3 原型重建的页面）
#
# 这个页面是「Vue 只接管内容区」的样板：
#   - 侧栏 / 顶栏 / 布局容器仍走 SciNote 原生（宿主 layout 提供）；
#   - 内容区是一个挂载点 #eln-project-detail，交给
#     ELN系统-Vue3/src/entries/project_detail.js 构建出的 bundle 接管；
#   - 数据由 ProjectDetailPayload 从真库取出，以 <script type="application/json"> 注入，
#     bundle 读它、覆盖 mock、渲染。没有第二个数据源。
#
# 权限沿用原生 Canaid 的读判断（can_read_project?），不另立一套 —— 与 access_control
# 的 D8「同源同层」原则一致：可不适用于可见性矩阵那个「管理」权限，但读页面必须能看。

module Scinote
  module ElnUi
    class ProjectDetailController < ApplicationController
      before_action :set_project
      before_action :check_project_read_permissions

      def show
        payload = Scinote::ElnUi::ProjectDetailPayload.call(@project)
        # </script> 会提前闭合注入块；< 一律转码，JSON 语义不变。
        @payload_json = JSON.generate(payload).gsub('<', '\\u003c')
        @payload = payload
      end

      # 报告 §5 第 6 项 #10：项目归档导出（结构化数据 CSV 预览包）。
      # 原生归档状态机由行菜单原生端点维护，本动作只聚合已有真相数据导出。
      def export
        csv = Scinote::ElnUi::ProjectArchiveExport.call(@project)
        send_data csv, filename: "project-#{@project.id}-archive.csv",
                  type: 'text/csv; charset=utf-8', disposition: 'attachment'
      end

      private

      def set_project
        @project = current_team.projects.active.find_by(id: params[:project_id])
        render_404 unless @project
      end

      def check_project_read_permissions
        return if respond_to?(:can_read_project?, true) && can_read_project?(@project)

        render_403
      end
    end
  end
end
