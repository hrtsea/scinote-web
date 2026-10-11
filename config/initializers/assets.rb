# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w( admin.js admin.css )

Rails.application.config.assets.precompile += %w(underscore.js)
Rails.application.config.assets.precompile += %w(jsPlumb-2.0.4-min.js)
Rails.application.config.assets.precompile += %w(jsnetworkx.js)
Rails.application.config.assets.precompile += %w(handsontable.full.js)
Rails.application.config.assets.precompile += %w(sugar.min.js jquerymy-1.2.14.min.js)
Rails.application.config.assets.precompile += %w(users/settings/list_toggle.js.erb)
Rails.application.config.assets.precompile += %w(users/settings/account/preferences/index.js)
Rails.application.config.assets.precompile += %w(users/settings/teams/add_user_modal.js)
# ⚠ 原登记的 users/settings/teams/show.js 已移除：该文件随 ADR-0034 迁移删除，
#   show.html.erb 改用 Vue 岛 vue_team_preferences。生产 assets.compile=false 下，
#   precompile 名单指向不存在的文件 ⇒ 预编译报错，故必须同步摘掉这条孤儿登记。
# 工作区创建表单 Vue 岛（宿主 webpack 构建，产物 app/assets/builds/vue_team_new.js）。
# 显式登记以遵守指南 §10.2 铁律 A：生产 assets.compile=false 下未登记 ⇒ AssetNotFound ⇒ 整页 500。
Rails.application.config.assets.precompile += %w(vue_team_new.js)
# 工作区（teams）列表页 Vue 岛（宿主 webpack 构建，产物 app/assets/builds/vue_teams_table.js）。
# 源码已从 addons/eln_ui 迁回宿主 app/javascript（与 vue_team_new 等宿主 team 页一致）。
Rails.application.config.assets.precompile += %w(vue_teams_table.js)
# 工作区设置/成员 Vue 岛（ADR-0034 迁回宿主后的产物）。
# ⚠ 这两条此前漏登记，但 show.html.erb / members.html.erb 已在引用它们，
#   且旧 users/settings/teams/show.js 已删除。生产 assets.compile=false 下未登记
#   ⇒ Sprockets AssetNotFound ⇒ 整页 500（指南 §10.2 铁律 A）。
Rails.application.config.assets.precompile += %w(vue_team_preferences.js)
Rails.application.config.assets.precompile += %w(vue_team_members.js)
Rails.application.config.assets.precompile += %w(users/settings/teams/invite_users_modal.js)
Rails.application.config.assets.precompile += %w(my_modules/activities.js)
Rails.application.config.assets.precompile += %w(my_modules/protocols.js)
Rails.application.config.assets.precompile += %w(my_modules/repositories.js)
Rails.application.config.assets.precompile += %w(my_modules/status_flow.js)
Rails.application.config.assets.precompile += %w(my_modules/protocols/protocol_status_bar.js)
Rails.application.config.assets.precompile += %w(my_modules/stock.js)
Rails.application.config.assets.precompile += %w(my_modules/assigned_users.js)
Rails.application.config.assets.precompile += %w(my_modules/archived.js)
Rails.application.config.assets.precompile += %w(my_modules/pwa_mobile_app.js)
Rails.application.config.assets.precompile += %w(assets/wopi/create_wopi_file.js)
Rails.application.config.assets.precompile += %w(results/result_tables.js)
Rails.application.config.assets.precompile += %w(results/result_assets.js)
Rails.application.config.assets.precompile += %w(results/result_texts.js)
Rails.application.config.assets.precompile += %w(jquery-ui/draggable.js)
Rails.application.config.assets.precompile += %w(jquery-ui/droppable.js)
Rails.application.config.assets.precompile += %w(jquery.ui.touch-punch.min.js)
Rails.application.config.assets.precompile += %w(bootstrap-colorselector.js)
Rails.application.config.assets.precompile += %w(emojione.js)
Rails.application.config.assets.precompile += %w(emojionearea.js)
Rails.application.config.assets.precompile += %w(eventPause-min.js)
Rails.application.config.assets.precompile += %w(sidebar.js)
Rails.application.config.assets.precompile += %w(shared/card_placeholder.js)
Rails.application.config.assets.precompile += %w(projects/index.js)
Rails.application.config.assets.precompile += %w(projects/canvas.js)
Rails.application.config.assets.precompile += %w(experiments/dropdown_actions.js)
Rails.application.config.assets.precompile += %w(experiments/table.js)
Rails.application.config.assets.precompile += %w(experiments/show.js)
Rails.application.config.assets.precompile += %w(protocols/index.js)
Rails.application.config.assets.precompile += %w(protocols/protocolsio.js)
Rails.application.config.assets.precompile += %w(protocols/header.js)
Rails.application.config.assets.precompile += %w(protocols/steps.js)
Rails.application.config.assets.precompile += %w(protocols/edit.js)
Rails.application.config.assets.precompile += %w(protocols/import_export/eln_table.js)
Rails.application.config.assets.precompile += %w(protocols/import_export/import.js)
Rails.application.config.assets.precompile += %w(protocols/import_export/export.js)
Rails.application.config.assets.precompile += %w(protocols/handson.js)
Rails.application.config.assets.precompile += %w(datatables.js)
Rails.application.config.assets.precompile += %w(search/index.js)
Rails.application.config.assets.precompile += %w(global_activities/side_pane.js)
Rails.application.config.assets.precompile += %w(navigation.js)
Rails.application.config.assets.precompile += %w(Sortable.min.js)
Rails.application.config.assets.precompile += %w(jszip.min.js)
Rails.application.config.assets.precompile += %w(comments.js)
Rails.application.config.assets.precompile += %w(projects/show.js)
Rails.application.config.assets.precompile += %w(notifications.js)
Rails.application.config.assets.precompile += %w(users/invite_users_modal.js)
Rails.application.config.assets.precompile += %w(search.js)
Rails.application.config.assets.precompile += %w(repositories/index.js)
Rails.application.config.assets.precompile += %w(repositories/share_modal.js)
Rails.application.config.assets.precompile += %w(repositories/edit.js)
Rails.application.config.assets.precompile += %w(repositories/repository_datatable.js)
Rails.application.config.assets.precompile += %w(repositories/show.js)
Rails.application.config.assets.precompile += %w(sidebar_toggle.js)
Rails.application.config.assets.precompile += %w(reports/reports_datatable.js)
Rails.application.config.assets.precompile += %w(reports/save_pdf_to_inventory.js)
Rails.application.config.assets.precompile += %w(reports/content.js)
Rails.application.config.assets.precompile += %w(session_end.js)
Rails.application.config.assets.precompile += %w(users/connected_devices.js)
Rails.application.config.assets.precompile += %w(BrowserPrint-3.0.216.min.js)
Rails.application.config.assets.precompile += %w(BrowserPrint-Zebra-1.0.216.min.js)
Rails.application.config.assets.precompile += %w(shared/color_picker_select.js)
Rails.application.config.assets.precompile += %w(users/registrations/new_with_provider.js)
Rails.application.config.assets.precompile += %w(repository_columns/manage_column_partials/number.js)
Rails.application.config.assets.precompile += %w(repository_columns/manage_column_partials/stock.js)
Rails.application.config.assets.precompile += %w(shared/file_preview.js)
Rails.application.config.assets.precompile += %w(reports/template_helpers.js)
Rails.application.config.assets.precompile += %w(shareable_links/date_formatting.js)
Rails.application.config.assets.precompile += %w(shareable_links/handson_table_wraping.js)

# Libraries needed for Handsontable formulas
Rails.application.config.assets.precompile += %w(jquery.js)
Rails.application.config.assets.precompile += %w(lodash.js)
Rails.application.config.assets.precompile += %w(numeral.js)
Rails.application.config.assets.precompile += %w(numeric.js)
Rails.application.config.assets.precompile += %w(md5.js)
Rails.application.config.assets.precompile += %w(jstat.js)
Rails.application.config.assets.precompile += %w(formula.js)
Rails.application.config.assets.precompile += %w(parser.js)
Rails.application.config.assets.precompile += %w(ruleJS.js)
Rails.application.config.assets.precompile += %w(handsontable.formula.js)
Rails.application.config.assets.precompile += %w(big.min.js)

# JQuery related includes
Rails.application.config.assets.precompile += %w(jquery_bundle.js)

# Separate icon font file
Rails.application.config.assets.precompile += %w(sn_icon_font.css)

# Separate translations file
Rails.application.config.assets.precompile += %w(i18n_bundle.js)

# ELN UI（addons/eln_ui）—— 前端迁移到宿主 webpack 构建后的资产登记说明。
#
# 6 个 ELN 页（project_list / res_center / workbench / project_detail / exp_detail /
# task_detail / apply_detail）的 JS+CSS 现已**全部**改为**宿主 webpack 构建**：
#   · 真源在 addons/eln_ui/app/javascript/vue/{eln,eln_project_list}/；
#   · 各 entry 在 config/webpack/webpack.config.js 注册为 eln_*；
#   · 产物输出到 app/assets/builds/eln_*.js + eln_*.css，视图用
#     javascript_include_tag 'eln_*' / stylesheet_link_tag 'eln_*' 引用。
#   ⚠ webpack 产物必须登记进 `assets.precompile`（见 addons/eln_ui/lib/scinote/eln_ui/engine.rb
#     initializer 'scinote_eln_ui.assets'），否则生产 assets.compile=false 下 AssetNotFound 整页 500。
#
# ✅ ADR-0038-D 起项目列表页 CSS 也并入 webpack（真源 …/eln_project_list/styles/
#    eln_project_list.scss），不再有「原型 blob 例外」，故此处无需再单独登记任何 ELN CSS。

# Add stuff installed by yarn
Rails.application.config.assets.paths << Rails.root.join('node_modules')
