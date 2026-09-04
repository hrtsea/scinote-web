require 'rails_helper'

# 临近截止 Widget（P7）局部渲染：柱状图挂载点 + 下钻列表均指向引擎 insights 端点
RSpec.describe 'dashboards/insights_due_dates partial', type: :view do
  before do
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    allow(Scinote::ProjectInsights).to receive(:enabled?).and_return(true)
  end

  it '把图表与下钻列表的 url 指向引擎 insights 端点' do
    render partial: 'dashboards/insights_due_dates',
           locals: { project_id: 42, widget: { size: 'col-md-6', position: 4 } }
    expect(rendered).to include('data-ajax-url="/insights?kind=due_dates')
    expect(rendered).to include('data-list-url="/insights/tasks?kind=due_dates')
    expect(rendered).not_to include('data-ajax-url="/assets')
    expect(rendered).not_to include('data-list-url="/assets')
    expect(rendered).to include('data-bucket="overdue"')
  end
end
