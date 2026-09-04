# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'dashboards/insights_bottlenecks partial', type: :view do
  # view spec 的隔离 view 实例不会自动注入引擎路由 helper；
  # 真实挂载视图（dashboard show 渲染该 partial）下 insights_path 可用。
  before do
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
  end

  it '渲染 7/14/<period>+ 天分组卡片并指向 bottlenecks 聚合端点' do
    render partial: 'dashboards/insights_bottlenecks',
           locals: { widget: { partial: 'dashboards/insights_bottlenecks', size: 'medium-widget', position: 2 } }

    expect(rendered).to include('data-ajax-url')
    expect(rendered).to include('/insights?kind=bottlenecks')
    # 官方 UI（frame_014）"No activity for:" 分段标签
    expect(rendered).to include('No activity for:')
    # 三个桶标签（i18n；fourteen 上界随 default_period_days 动态插值）
    expect(rendered).to include('7-14 days')
    expect(rendered).to include("14-#{Scinote::ProjectInsights.default_period_days} days")
    expect(rendered).to include('90+ days')
    # 三个数量占位 + 下钻钩子
    expect(rendered).to include('data-count="seven"')
    expect(rendered).to include('data-count="fourteen"')
    expect(rendered).to include('data-count="thirty_plus"')
    expect(rendered).to include('data-drilldown')
  end

  # 三档全为 0 时由 JS 取消 hidden 显示；默认渲染为隐藏。
  it '渲染默认隐藏的空状态（Well done. ...），供 JS 在全零时展示' do
    render partial: 'dashboards/insights_bottlenecks',
           locals: { widget: { partial: 'dashboards/insights_bottlenecks', size: 'medium-widget', position: 2 } }

    expect(rendered).to include('data-empty-state')
    expect(rendered).to include('Well done.')
    expect(rendered).to include('All tasks had some activity within the last 7 days.')
    expect(rendered).to match(/<div class="bottleneck-empty" data-empty-state[^>]*hidden/)
  end

  # 待补 G：卡片点击在 widget 内联渲染档内任务列表（不再直接跳转）。
  it '挂载档内任务列表面板与 data-bucket / data-list-url 钩子' do
    render partial: 'dashboards/insights_bottlenecks',
           locals: { widget: { partial: 'dashboards/insights_bottlenecks', size: 'medium-widget', position: 2 } }

    expect(rendered).to include('data-list-url')
    expect(rendered).to include('/insights/tasks?kind=bottlenecks')
    %w(seven fourteen thirty_plus).each do |bucket|
      expect(rendered).to include("data-bucket=\"#{bucket}\"")
    end
    expect(rendered).to include('data-bucket-task-list')
    expect(rendered).to include('data-bucket-list-items')
    expect(rendered).to include('View all in Current Tasks')
  end
end
