# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'dashboards/insights_due_dates partial', type: :view do
  # view spec 的隔离 view 实例不会自动注入引擎路由 helper；
  # 真实挂载视图（dashboard show 渲染该 partial）下 insights_path 可用。
  before do
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
  end

  # 档位集合对齐 frame_014 官方 UI：Overdue 独立成档，无 "More weeks"。
  it '渲染 Overdue/Today/Tomorrow/This week/Next week 五档卡片并指向 due_dates 聚合端点' do
    render partial: 'dashboards/insights_due_dates',
           locals: { widget: { partial: 'dashboards/insights_due_dates', size: 'medium-widget', position: 3 } }

    expect(rendered).to include('data-ajax-url')
    expect(rendered).to include('/insights?kind=due_dates')
    # 五个档标签（i18n）
    expect(rendered).to include('Overdue')
    expect(rendered).to include('Today')
    expect(rendered).to include('Tomorrow')
    expect(rendered).to include('This week')
    expect(rendered).to include('Next week')
    # 五个数量占位 + 下钻钩子
    %w(overdue today tomorrow this_week next_week).each do |bucket|
      expect(rendered).to include("data-count=\"#{bucket}\"")
    end
    expect(rendered).to include('data-drilldown')
  end

  # 待补 G：卡片点击在 widget 内联渲染档内任务列表（不再直接跳转）。
  it '挂载档内任务列表面板与 data-bucket / data-list-url 钩子' do
    render partial: 'dashboards/insights_due_dates',
           locals: { widget: { partial: 'dashboards/insights_due_dates', size: 'medium-widget', position: 3 } }

    expect(rendered).to include('data-list-url')
    expect(rendered).to include('/insights/tasks?kind=due_dates')
    %w(overdue today tomorrow this_week next_week).each do |bucket|
      expect(rendered).to include("data-bucket=\"#{bucket}\"")
    end
    expect(rendered).to include('data-bucket-task-list')
    expect(rendered).to include('data-bucket-list-items')
    expect(rendered).to include('View all in Current Tasks')
  end
end
