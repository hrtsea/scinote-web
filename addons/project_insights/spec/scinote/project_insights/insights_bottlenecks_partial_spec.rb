# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'dashboards/insights_bottlenecks partial', type: :view do
  # view spec 的隔离 view 实例不会自动注入引擎路由 helper；
  # 真实挂载视图（dashboard show 渲染该 partial）下 insights_path 可用。
  before do
    allow(view).to receive(:dashboard_current_tasks_path).and_return('/dashboard/current_tasks')
    view.extend(Scinote::ProjectInsights::Engine.routes.url_helpers)
  end

  it '渲染 7/14/30+ 天分组卡片并指向 bottlenecks 聚合端点' do
    render partial: 'dashboards/insights_bottlenecks',
           locals: { widget: { partial: 'dashboards/insights_bottlenecks', size: 'medium-widget', position: 2 } }

    expect(rendered).to include('data-ajax-url')
    expect(rendered).to include('/insights?kind=bottlenecks')
    # 三个桶标签（i18n）
    expect(rendered).to include('7-14 days')
    expect(rendered).to include('14-30 days')
    expect(rendered).to include('30+ days')
    # 三个数量占位 + 下钻钩子
    expect(rendered).to include('data-count="seven"')
    expect(rendered).to include('data-count="fourteen"')
    expect(rendered).to include('data-count="thirty_plus"')
    expect(rendered).to include('data-drilldown')
  end
end
