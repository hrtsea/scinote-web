# frozen_string_literal: true

# 在 dashboard 页面 <head> 注入 insights_charts pack（仅当 addon 启用时）。
# 通过 prepend 重写 DashboardsController#show，在渲染前（layout yield :head 时）
# 追加 JS tag；关闭 addon 时不注入（零渲染零查询，与 enabled? 门控一致）。
module Scinote
  module ProjectInsights
    module DashboardsControllerDecorator
      def show
        view_flow.content_for(:head) { javascript_include_tag 'insights_charts' } if Scinote::ProjectInsights.enabled?
        super
      end
    end
  end
end

DashboardsController.prepend(Scinote::ProjectInsights::DashboardsControllerDecorator)
