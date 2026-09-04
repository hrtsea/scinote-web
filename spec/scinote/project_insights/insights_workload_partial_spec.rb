require 'rails_helper'

# 工作量分布 Widget（P5）局部渲染：柱状图挂载点需指向引擎 insights 端点
RSpec.describe 'dashboards/insights_workload partial', type: :view do
  before do
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    allow(Scinote::ProjectInsights).to receive(:enabled?).and_return(true)
  end

  it '把柱状图挂载点的 ajax-url 指向引擎 insights 端点' do
    render partial: 'dashboards/insights_workload',
           locals: { project_id: 42, widget: { size: 'col-md-6', position: 2 } }
    expect(rendered).to include('data-insights-chart="bar"')
    expect(rendered).to include('/insights?kind=workload')
    expect(rendered).to include('data-user-count-template')
  end
end
