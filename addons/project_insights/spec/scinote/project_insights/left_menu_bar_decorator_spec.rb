# frozen_string_literal: true

require 'rails_helper'

# 回归锁（2026-09-04 实测故障）：addon 的 left_menu_insights_extension 曾在**宿主**
# helper 上下文里直接调用 insights_path。引擎是 isolate_namespace 的独立 RouteSet，
# 宿主视图上下文没有该 helper，于是所有渲染左侧菜单的页面（shared/navigation/_left）
# 抛 NameError → 500。helper spec 的上下文与生产渲染一致，可复现该故障。
RSpec.describe LeftMenuBarHelper, type: :helper do
  it 'addon 启用时把 Insights 菜单项插到 Dashboard 之后' do
    menu = helper.left_menu_elements
    insights = menu.find { |item| item[:url] == '/insights' }

    expect(insights).to include(icon: 'sn-icon-Insights',
                                name: I18n.t('left_menu_bar.insights'))
    expect(menu.index(insights)).to eq(1)
  end

  it 'addon 禁用时不注入 Insights 菜单项' do
    AddonSetting.create!(name: 'project_insights', enabled: false, configuration: {})

    expect(helper.left_menu_elements.pluck(:url)).not_to include('/insights')
  end
end
