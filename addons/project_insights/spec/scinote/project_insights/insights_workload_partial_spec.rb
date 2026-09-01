# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'dashboards/insights_workload partial', type: :view do
  # view spec 的隔离 view 实例不会自动注入引擎路由 helper；
  # 真实挂载视图（dashboard show 渲染该 partial）下 insights_path 可用。
  before do
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
  end

  it '挂载堆叠柱图 div 并指向 workload 聚合端点' do
    render partial: 'dashboards/insights_workload',
           locals: { widget: { partial: 'dashboards/insights_workload', size: 'medium-widget', position: 4 } }

    expect(rendered).to include('data-insights-chart="bar"')
    expect(rendered).to include('data-ajax-url')
    expect(rendered).to include('/insights?kind=workload')
  end
end
