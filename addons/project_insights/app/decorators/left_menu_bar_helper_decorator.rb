# frozen_string_literal: true

# Adds a "Project Insights" entry to the host app's left menu bar.
#
# Core exposes an official extension hook in `LeftMenuBarHelper#left_menu_elements`
# (app/helpers/left_menu_bar_helper.rb): any private method matching
# `left_menu_*_extension` is invoked with the menu array and may return a
# mutated copy. This lets the addon inject its entry WITHOUT modifying any
# core file (addons-zero-intrusion rule).
#
# Loaded by the engine's `to_prepare` block
# (lib/scinote/project_insights/engine.rb), which globs `*_decorator*.rb`.
LeftMenuBarHelper.module_eval do
  private

  def left_menu_insights_extension(menu)
    return menu unless Scinote::ProjectInsights.enabled?

    # Insert right after "Dashboard" (index 0) so Insights sits at the top
    # of the analytics group, matching the product UI.
    menu.insert(1, {
                  url: insights_menu_path,
                  name: I18n.t('left_menu_bar.insights'),
                  icon: 'sn-icon-Insights',
                  active: insights_are_selected?
                })
    menu
  end

  def insights_are_selected?
    controller_name == 'insights'
  end

  # ⚠️ 2026-09-04 实测故障修复：引擎是 isolate_namespace 的**独立 RouteSet**，
  # 宿主视图/helper 上下文里没有 insights_path，直接调用会抛 NameError，
  # 导致所有渲染左侧菜单的页面 500（宿主 shared/navigation/_left.html.erb:2）。
  # 故显式经引擎的 url_helpers 取路径（引擎挂载在 '/'，产出 '/insights'）。
  def insights_menu_path
    Scinote::ProjectInsights::Engine.routes.url_helpers.insights_path
  end
end
