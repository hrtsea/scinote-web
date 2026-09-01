# frozen_string_literal: true

require 'rails_helper'

# 下钻联动（P8）：四个 widget 的 partial 都须注入 data-drilldown-base（指向
# current_tasks），且卡片 widget 携带 data-drilldown 钩子（JS 据此构造跳转 URL）。
RSpec.describe 'dashboards/insights widget 下钻基座', type: :view do
  before do
    # 隔离 view spec 无法解析嵌套 singular 路由 helper（dashboard_current_tasks_path），
    # 生产由真实路由提供；此处 stub 为其输出，断言 partial 正确内联了该基座 URL。
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
  end

  it '四个 widget 均注入 data-drilldown-base 指向 current_tasks' do
    %w(insights_status insights_workload insights_bottlenecks insights_due_dates).each do |partial|
      render partial: "dashboards/#{partial}",
             locals: { widget: { partial: "dashboards/#{partial}", size: 'medium-widget', position: 1 } }
      expect(rendered).to include('data-drilldown-base')
      expect(rendered).to include('/dashboard/current_tasks')
    end
  end

  it '卡片 widget 携带 data-drilldown 钩子' do
    render partial: 'dashboards/insights_bottlenecks',
           locals: { widget: { partial: 'dashboards/insights_bottlenecks', size: 'medium-widget', position: 1 } }
    expect(rendered).to include('data-drilldown="bottlenecks:')

    render partial: 'dashboards/insights_due_dates',
           locals: { widget: { partial: 'dashboards/insights_due_dates', size: 'medium-widget', position: 1 } }
    expect(rendered).to include('data-drilldown="due_dates:')
  end
end
