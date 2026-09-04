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

  # 官方 UI（frame_014）：标题右侧为成员筛选 "N options selected"，
  # N 由 JS 依聚合结果的 distinct 用户数填充，模板（含 %{count} 占位）由 i18n 提供。
  it '提供成员筛选计数模板（data-user-count-template）' do
    render partial: 'dashboards/insights_workload',
           locals: { widget: { partial: 'dashboards/insights_workload', size: 'medium-widget', position: 4 } }

    # 占位符由 JS 替换为实际人数；拆开百分号构造，避免被误判为格式化模板 token
    percent = '%'
    expect(rendered).to include("data-user-count-template=\"#{percent}{count} options selected\"")
  end

  # D 可交互成员多选：挂载成员筛选容器与标题（JS 依负载数据填充勾选框）。
  it '挂载成员多选容器 data-member-filter / data-member-filter-items 与标题' do
    render partial: 'dashboards/insights_workload',
           locals: { widget: { partial: 'dashboards/insights_workload', size: 'medium-widget', position: 4 } }

    expect(rendered).to include('data-member-filter')
    expect(rendered).to include('data-member-filter-items')
    expect(rendered).to include('Members')
  end
end
