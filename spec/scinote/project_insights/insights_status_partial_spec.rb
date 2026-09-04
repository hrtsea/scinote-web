require 'rails_helper'

# Status Overview Widget（P4）局部渲染：饼图挂载点需指向引擎 insights 端点
RSpec.describe 'dashboards/insights_status partial', type: :view do
  before do
    # addon 视图默认未混入引擎路由 helper，需在隔离的 view spec 中手动注入
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
    view.extend(Rails.application.routes.url_helpers)
    # 隔离 view spec 解析不到 dashboard engine 的具名路由，stub 掉下钻基址即可
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    allow(Scinote::ProjectInsights).to receive(:enabled?).and_return(true)
  end

  it '把饼图挂载点的 ajax-url 指向引擎 insights 端点' do
    render partial: 'dashboards/insights_status',
           locals: { project_id: 42, widget: { size: 'col-md-6', position: 1 } }
    expect(rendered).to include('data-insights-chart="pie"')
    expect(rendered).to include('/insights?kind=status')
    expect(rendered).to include('data-total-label')
  end
end
