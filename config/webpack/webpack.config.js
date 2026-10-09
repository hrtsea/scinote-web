const path = require('path');
const webpack = require('webpack');
const { VueLoaderPlugin } = require('vue-loader');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const RemoveEmptyScriptsPlugin = require('webpack-remove-empty-scripts');
const NodePolyfillPlugin = require('node-polyfill-webpack-plugin');
const { execSync } = require('child_process');
const { basename, resolve } = require('path');
const { readdirSync } = require('fs');
const mode = process.env.NODE_ENV === 'development' ? 'development' : 'production';
const fs = require('fs');

const entryList = {
  application_pack: './app/javascript/packs/application.js',
  application_pack_styles: './app/javascript/packs/application.scss',
  bootstrap_pack: './app/javascript/packs/bootstrap.less',
  emoji_button: './app/javascript/packs/emoji_button.js',
  fontawesome: './app/javascript/packs/fontawesome.scss',
  prism: './app/javascript/packs/prism.js',
  tiny_mce: './app/javascript/packs/tiny_mce.js',
  tiny_mce_styles: './app/javascript/packs/tiny_mce_styles.scss',
  tui_image_editor: './app/javascript/packs/tui_image_editor.js',
  tui_image_editor_styles: './app/javascript/packs/tui_image_editor_styles.scss',
  croppie: './app/javascript/packs/custom/croppie.js',
  croppie_styles: './app/javascript/packs/custom/croppie_styles.scss',
  inputmask: './app/javascript/packs/custom/inputmask.js',
  pdfjs: './app/javascript/packs/pdfjs/pdf_js.js',
  pdf_js_styles: './app/javascript/packs/pdfjs/pdf_js_styles.scss',
  pdf_js: './app/javascript/packs/pdfjs/pdf_js.js',
  pdf_js_worker: './app/javascript/packs/pdfjs/pdf_js_worker.js',
  vue_label_template: './app/javascript/packs/vue/label_template.js',
  vue_protocol: './app/javascript/packs/vue/protocol.js',
  vue_results: './app/javascript/packs/vue/results.js',
  vue_repository_filter: './app/javascript/packs/vue/repository_filter.js',
  vue_repository_search: './app/javascript/packs/vue/repository_search.js',
  vue_repository_print_modal: './app/javascript/packs/vue/repository_print_modal.js',
  vue_repository_assign_items_to_task_modal: './app/javascript/packs/vue/assign_items_to_task_modal.js',
  vue_share_task_container: './app/javascript/packs/vue/share_task_container.js',
  vue_navigation_top_menu: './app/javascript/packs/vue/navigation/top_menu.js',
  vue_navigation_navigator: './app/javascript/packs/vue/navigation/navigator.js',
  vue_components_repository_item_sidebar: './app/javascript/packs/vue/repository_item_sidebar.js',
  vue_components_repository_item_error_sidebar: './app/javascript/packs/vue/repository_item_error_sidebar.js',
  vue_components_action_toolbar: './app/javascript/packs/vue/action_toolbar.js',
  vue_components_open_vector_editor: './app/javascript/packs/vue/open_vector_editor.js',
  vue_navigation_breadcrumbs: './app/javascript/packs/vue/navigation/breadcrumbs.js',
  vue_components_repository_item_relationships: './app/javascript/packs/vue/repository_item_relationships.js',
  vue_components_export_stock_consumption_modal: './app/javascript/packs/vue/export_stock_consumption_modal.js',
  vue_user_preferences: './app/javascript/packs/vue/user_preferences.js',
  vue_components_manage_stock_value_modal: './app/javascript/packs/vue/manage_stock_value_modal.js',
  vue_legacy_datetime_picker: './app/javascript/packs/vue/legacy/datetime_picker.js',
  vue_label_templates_table: './app/javascript/packs/vue/label_templates_table.js',
  vue_projects_list: './app/javascript/packs/vue/projects_list.js',
  vue_experiments_list: './app/javascript/packs/vue/experiments_list.js',
  vue_my_modules_list: './app/javascript/packs/vue/my_modules_list.js',
  vue_design_system_select: './app/javascript/packs/vue/design_system/select.js',
  vue_design_system_breadcrumbs: './app/javascript/packs/vue/design_system/breadcrumbs.js',
  vue_protocols_list: './app/javascript/packs/vue/protocols_list.js',
  vue_repositories_table: './app/javascript/packs/vue/repositories_table.js',
  vue_import_repository_modal: './app/javascript/packs/vue/import_repository_modal.js',
  vue_reports_table: './app/javascript/packs/vue/reports_table.js',
  vue_reports_new: './app/javascript/packs/vue/reports_new.js',
  vue_open_locally_menu: './app/javascript/packs/vue/open_locally_menu.js',
  vue_scinote_edit_download: './app/javascript/packs/vue/scinote_edit_download.js',
  vue_design_system_modals: './app/javascript/packs/vue/design_system/modals.js',
  vue_global_search: './app/javascript/packs/vue/global_search.js',
  vue_legacy_tags_modal: './app/javascript/packs/vue/legacy/tags_modal.js',
  vue_legacy_access_modal: './app/javascript/packs/vue/legacy/access_modal.js',
  vue_legacy_new_task_modal: './app/javascript/packs/vue/legacy/new_task_modal.js',
  vue_legacy_repository_menu_dropdown: './app/javascript/packs/vue/legacy/repository_menu_dropdown.js',
  vue_dashboard_new_task: './app/javascript/packs/vue/dashboard_new_task.js',
  vue_storage_locations_table: './app/javascript/packs/vue/storage_locations_table.js',
  vue_storage_locations_container: './app/javascript/packs/vue/storage_locations_container.js',
  vue_form_show: './app/javascript/packs/vue/forms_show.js',
  vue_form_table: './app/javascript/packs/vue/forms_table.js',
  vue_my_module_assigned_items: './app/javascript/packs/vue/my_module_assigned_items.js',
  vue_design_system_inputs: './app/javascript/packs/vue/design_system/inputs.js',
  vue_design_system_table: './app/javascript/packs/vue/design_system/table.js',
  vue_design_system_charts: './app/javascript/packs/vue/design_system/charts.js',
  vue_design_system_datepicker: './app/javascript/packs/vue/design_system/datepicker.js',
  vue_design_system_input_titles: './app/javascript/packs/vue/design_system/input_title.js',
  vue_favorites_widget: './app/javascript/packs/vue/favorites_widget.js',
  vue_experiment_description_modal: './app/javascript/packs/vue/experiment_description_modal.js',
  vue_user_groups_table: './app/javascript/packs/vue/user_groups_table.js',
  vue_user_groups_show: './app/javascript/packs/vue/user_groups_show.js',
  vue_my_module_show: './app/javascript/packs/vue/my_module_show.js',
  vue_tags_table: './app/javascript/packs/vue/tags_table.js',
  vue_webhooks: './app/javascript/packs/vue/webhooks.js',
  vue_label_printers: './app/javascript/packs/vue/label_printers.js',
  vue_team_automations: './app/javascript/packs/vue/team_automations.js',
  vue_protocol_versions: './app/javascript/packs/vue/protocol_versions.js',
  vue_protocol_repository_rows: './app/javascript/packs/vue/protocol_repository_rows.js',
  vue_team_preferences: './app/javascript/packs/vue/team_preferences.js',
  vue_shareable_links_my_module_assigned_items: './app/javascript/packs/vue/shareable_links/assigned_repository.js',
  vue_equipment_bookings: './app/javascript/packs/vue/equipment_bookings.js',
  vue_event_create_repository_row: './app/javascript/packs/vue/event_create_repository_row.js',
  vue_my_module_archive: './app/javascript/packs/vue/my_module_archive.js',
  vue_protocol_report_templates: './app/javascript/packs/vue/protocol_report_templates.js',
  vue_my_module_reports: './app/javascript/packs/vue/my_module_reports.js',
  // --- 本轮 Vue 3 迁移新增 entry（Gen-1 页面迁移）---
  vue_assets_office: './app/javascript/packs/vue/assets_office.js',
  vue_user_confirmation_new: './app/javascript/packs/vue/user_confirmation_new.js',
  vue_user_invitation_edit: './app/javascript/packs/vue/user_invitation_edit.js',
  vue_user_registration_new: './app/javascript/packs/vue/user_registration_new.js',
  vue_global_activities: './app/javascript/packs/vue/global_activities.js',
  vue_team_members: './app/javascript/packs/vue/team_members.js',
  vue_user_registration_edit: './app/javascript/packs/vue/user_registration_edit.js',
  vue_login_disclaimer: './app/javascript/packs/vue/login_disclaimer.js',
  vue_linkedin_sign_in: './app/javascript/packs/vue/linkedin_sign_in.js',
  vue_new_protocol_modal: './app/javascript/packs/vue/new_protocol_modal.js',
  vue_shareable_protocol_show: './app/javascript/packs/vue/shareable_protocol_show.js',
  vue_shareable_results_show: './app/javascript/packs/vue/shareable_results_show.js',
  // project_insights addon: 在 dashboard 渲染状态饼图等 widget
  insights_charts: './addons/project_insights/app/javascript/packs/insights_charts.js',
  // eln_ui addon: 工作区列表 Vue 化（源码在 addons/eln_ui/app/javascript，宿主 webpack 构建）
  vue_teams_table: './addons/eln_ui/app/javascript/packs/vue_teams_table.js',
  // eln_ui addon: 项目列表接入原生 AG Grid 栈（引用 shared/datatable，非复制）。
  // 产物输出到 app/assets/builds/eln_project_list.js，视图用 javascript_include_tag 'eln_project_list'。
  eln_project_list: './addons/eln_ui/app/javascript/packs/eln_project_list.js',
  // --- ELN 系统 Vue3 内嵌页（资源中心 / 工作台 / 项目详情 / 实验详情 / 任务详情 / 申请详情）---
  // 真源统一在 addons/eln_ui/app/javascript/vue/eln/（与 Vue3 原型 ELN系统-Vue3 同一份组件），
  // 各 pack 仅 re-import 对应 entry（entry 在加载时读 window.__ELN_*__ 并挂载到 #eln-*）。
  // 产物输出到 app/assets/builds/eln_*.js + eln_*.css，视图用 javascript_include_tag 'eln_*'。
  eln_res_center: './addons/eln_ui/app/javascript/packs/eln_res_center.js',
  eln_workbench: './addons/eln_ui/app/javascript/packs/eln_workbench.js',
  eln_project_detail: './addons/eln_ui/app/javascript/packs/eln_project_detail.js',
  eln_exp_detail: './addons/eln_ui/app/javascript/packs/eln_exp_detail.js',
  eln_task_detail: './addons/eln_ui/app/javascript/packs/eln_task_detail.js',
  eln_apply_detail: './addons/eln_ui/app/javascript/packs/eln_apply_detail.js'
};

// Engine pack loading based on https://github.com/rails/webpacker/issues/348#issuecomment-635480949
// Get paths to all engines' folders
console.log('Including packs from addons...');

let enginePaths = [];

try {
  enginePaths = execSync('ls -d $PWD/addons/*').toString().split('\n').filter((p) => !!p);
} catch {
  console.log('Unable to find any addons.');
}

enginePaths.forEach((path) => {
  console.log(`Checking for engine extra yarn packages in ${path}...`)
  let extraYarnPackages

  try {
    extraYarnPackages = execSync(`[ -f ${path}/app/javascript/extra_yarn_packages.txt ] && cat ${path}/app/javascript/extra_yarn_packages.txt`).toString().split('\n').filter((p) => !!p);
  } catch {
    extraYarnPackages = [];
  }

  // --- Load resolutions ---
  const resolutionsFile = `${path}/app/javascript/extra_yarn_resolutions.json`;
  let extraResolutions = {};
  if (fs.existsSync(resolutionsFile)) {
    console.log(`Found extra Yarn resolutions in ${resolutionsFile}`);
    try {
      extraResolutions = JSON.parse(fs.readFileSync(resolutionsFile, 'utf8'));
    } catch (e) {
      console.error(`Failed to parse ${resolutionsFile}:`, e.message);
    }
  }

  // --- Merge resolutions into package.json ---
  if (Object.keys(extraResolutions).length > 0) {
    const packageJsonPath = './package.json';
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));

    packageJson.resolutions = packageJson.resolutions || {};
    Object.assign(packageJson.resolutions, extraResolutions);

    // Save updated package.json
    fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2));
    console.log("Merged resolutions into root package.json");
  }

  if (extraYarnPackages.length > 0) {
    extraYarnPackages.forEach((extraPackage) => {
      console.log(`Adding ${extraPackage}`);
      execSync(`yarn add ${extraPackage}`);
    });
  } else {
    console.log(`No extra yarn packages in ${path}.`);
  }

  if (mode === 'production') {
    console.log(`Checking for engine JS file overrides in ${path}...`)
    let jsFileOverrides

    try {
      jsFileOverrides = execSync(`[ -f ${path}/app/javascript/overrides.txt ] && cat ${path}/app/javascript/overrides.txt`).toString().split('\n').filter((p) => !!p);
    } catch {
      jsFileOverrides = [];
    }

    if (jsFileOverrides.length > 0) {
      jsFileOverrides.forEach((jsFilePath) => {
        console.log(`Overwritting ${jsFilePath}...`);
        execSync(`\\cp -f ${path}/${jsFilePath} ./${jsFilePath}`);
      });
    } else {
      console.log(`No JS file overrides in ${path}.`);
    }
  }

  const packsFolderPath = `${path}/app/javascript/packs`;

  let entryFiles;
  try {
    entryFiles = readdirSync(packsFolderPath);
    console.log(`Found packs in ${path}`);
  } catch {
    console.log(`No packs in ${path}`);
    return;
  }

  entryFiles.forEach((file) => {
    // File name without .js
    const fileName = basename(file, '.js');
    const entryPath = `${packsFolderPath}/${file}`;

    entryList[fileName] = entryPath;
  });
});

module.exports = {
  mode,
  optimization: {
    moduleIds: 'deterministic'
  },
  entry: entryList,
  output: {
    filename: '[name].js',
    sourceMapFilename: '[file].map',
    path: path.resolve(__dirname, '..', '..', 'app/assets/builds')
  },
  externals: {
    $: 'jquery',
    jquery: 'jQuery',
    moment: 'moment'
  },
  module: {
    rules: [
      {
        test: /\.vue$/,
        use: 'vue-loader'
      },
      {
        test: /\.(js)$/,
        exclude: /node_modules/,
        use: ['babel-loader']
      },
      {
        test: /\.less$/i,
        use: [
          MiniCssExtractPlugin.loader,
          "css-loader",
          "less-loader",
        ],
      },
      {
        test: /\.(?:sa|sc|c)ss$/i,
        use: [MiniCssExtractPlugin.loader, 'css-loader', 'sass-loader']
      },
      {
        test: /\.(png|jpe?g|gif|svg)$/i,
        use: 'file-loader'
      }
    ]
  },
  resolve: {
    // Add additional file types
    extensions: ['.js', '.jsx', '.scss', '.css', '.vue', '.less'],
    // eln_ui 引用宿主原生 shared/datatable（AG Grid 栈）时使用，避免跨 addon 的长相对路径
    // __dirname 在 config/webpack/ 下，需 ../.. 回到应用根再进 app/javascript/vue/shared
    alias: {
      shared: resolve(__dirname, '..', '..', 'app/javascript/vue/shared'),
      // addon 引用宿主原生 vue 组件（**非 shared 子目录**，如 repositories/table.vue）时使用。
      // 与 shared 同理：避免跨 addon 的 7 级长相对路径；且解析到同一绝对路径 ⇒ 与 addon
      // 侧 `shared/...` 引用的是**同一个模块实例**（webpack 按绝对路径去重，不会出现两份 AG Grid）。
      host: resolve(__dirname, '..', '..', 'app/javascript/vue'),
      // addon 代码跨边界引用宿主原生 axios（含 CSRF 注入），避免 ../../../.. 长相对路径
      custom_axios: resolve(__dirname, '..', '..', 'app/javascript/packs/custom_axios.js')
    }
  },
  plugins: [
    new webpack.optimize.LimitChunkCountPlugin({
      maxChunks: 1
    }),
    new webpack.DefinePlugin({
      __VUE_OPTIONS_API__: true,
      __VUE_PROD_DEVTOOLS__: false,
      __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: false
    }),
    new VueLoaderPlugin(),
    new RemoveEmptyScriptsPlugin(),
    new MiniCssExtractPlugin(),
    new NodePolyfillPlugin()
  ]
};
