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
Rails.application.config.assets.precompile += %w(users/settings/teams/show.js)
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
# 除项目列表页外，其余 5 页（res_center / workbench / project_detail / exp_detail /
# task_detail / apply_detail）的 JS+CSS 已全部改为**宿主 webpack 构建**：
#   · 真源在 addons/eln_ui/app/javascript/vue/eln/（与 Vue3 原型 ELN系统-Vue3 同一份组件）；
#   · 各 entry 在 config/webpack/webpack.config.js 注册为 eln_*；
#   · 产物输出到 app/assets/builds/eln_*.js + eln_*.css，视图用
#     javascript_include_tag 'eln_*' / stylesheet_link_tag 'eln_*' 引用。
#   webpack 产物不走 Sprockets 预编译（与 eln_project_list 同机制），故此处无需登记。
#
# ⚠ 仅剩项目列表页的 CSS 仍沿用原型 vite 单独打包的 blob：列表页 SFC 自身无 <style>，
#   样式完全由该 blob（eln_vue3/eln_project_list.css）承载，且列表页 JS 已走宿主 webpack
#   的 eln_project_list entry。故此处只保留这一条 CSS 登记，删 blob 时切勿一并删掉。
Rails.application.config.assets.precompile += %w(
  eln_vue3/eln_project_list.css
)

# Add stuff installed by yarn
Rails.application.config.assets.paths << Rails.root.join('node_modules')
