# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'dashboards/insights_status partial', type: :view do
  # view spec 的隔离 view 实例不会自动注入引擎路由 helper；
  # 真实挂载视图（dashboard show 渲染该 partial）下 insights_path 可用。
  before do
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
  end

  it '挂载饼图 div 并指向 status 聚合端点' do
    render partial: 'dashboards/insights_status',
           locals: { widget: { partial: 'dashboards/insights_status', size: 'medium-widget', position: 4 } }

    expect(rendered).to include('data-insights-chart="pie"')
    expect(rendered).to include('data-ajax-url')
    expect(rendered).to include('/insights?kind=status')
  end
end
