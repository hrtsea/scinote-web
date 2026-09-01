# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'dashboards/insights_due_dates partial', type: :view do
  # view spec 的隔离 view 实例不会自动注入引擎路由 helper；
  # 真实挂载视图（dashboard show 渲染该 partial）下 insights_path 可用。
  before do
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
  end

  it '渲染 逾期/今天/本周/即将 四档分组卡片并指向 due_dates 聚合端点' do
    render partial: 'dashboards/insights_due_dates',
           locals: { widget: { partial: 'dashboards/insights_due_dates', size: 'medium-widget', position: 3 } }

    expect(rendered).to include('data-ajax-url')
    expect(rendered).to include('/insights?kind=due_dates')
    # 四个档标签（i18n）
    expect(rendered).to include('Overdue')
    expect(rendered).to include('Due today')
    expect(rendered).to include('Due this week')
    expect(rendered).to include('Upcoming')
    # 四个数量占位 + 下钻钩子
    expect(rendered).to include('data-count="overdue"')
    expect(rendered).to include('data-count="due_today"')
    expect(rendered).to include('data-count="due_this_week"')
    expect(rendered).to include('data-count="upcoming"')
    expect(rendered).to include('data-drilldown')
  end
end
