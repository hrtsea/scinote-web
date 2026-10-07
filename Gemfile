# frozen_string_literal: true

source 'https://rubygems.org'

ruby '~> 3.4.8'

gem 'activerecord-session_store'
gem 'bootsnap', require: false
gem 'devise', '~> 5.0.4'
gem 'devise_invitable'
gem 'pg', '~> 1.5'
gem 'puma'
gem 'rails', '~> 7.2.3'
gem 'recaptcha'
gem 'sanitize'
gem 'solid_cable', '~> 3.0'
gem 'sprockets-rails'
gem 'view_component'

# ===== AI 助手（ActiveAgent）—— 实现 ai_eln 的全部能力 =====
# activeagent : agent 运行时 + action 能力单元 + 可观测面板
# actionagent : 开发期 dashboard（trace / token / 成本），挂 /activeagents
# ruby_llm    : ActiveAgent 的推理后端（DeepSeek 经 OpenAI 兼容）；activeagent 已传递依赖，此处显式声明便于 pin
gem 'activeagent', '~> 1.7'
gem 'actionagent', '~> 1.7'
gem 'ruby_llm'

# Gems for OAuth2 subsystem
gem 'doorkeeper', '>= 4.6'
gem 'omniauth', '~> 2.1'
gem 'omniauth-azure-activedirectory-v2'
gem 'omniauth-linkedin-oauth2'
gem 'omniauth-okta', git: 'https://github.com/scinote-eln/omniauth-okta', branch: 'org_auth_server_support'
gem 'omniauth_openid_connect'
gem 'omniauth-rails_csrf_protection', '~> 1.0'
gem 'omniauth-saml'

# Gems for API implementation
gem 'active_model_serializers', '~> 0.10.15'
gem 'json-jwt'
gem 'jwt'
gem 'kaminari'
gem 'rack'
gem 'rack-attack'
gem 'rack-cors'
gem 'rack-session'

gem 'activerecord-import', '~> 2.2.0'
gem 'acts_as_list'
gem 'ajax-datatables-rails', '~> 0.3.1'
gem 'auto_strip_attributes', '~> 2.1' # Removes unnecessary whitespaces AR
gem 'bcrypt', '~> 3.1.22'
# gem 'caracal'
gem 'caracal', git: 'https://github.com/scinote-eln/caracal.git', branch: 'custom-docx-reports' # Build docx report
gem 'caxlsx' # Build XLSX files
gem 'deface', '~> 1.9'
gem 'down', '~> 5.0'
gem 'fastimage' # Light gem to get image resolution
gem 'grover'
gem 'httparty', '~> 0.24.0'
gem 'i18n-js', '~> 3.6' # Localization in javascript files
gem 'jbuilder' # JSON structures via a Builder-style DSL
gem 'mime-types', '~> 3.4'
gem 'nested_form_fields'
gem 'nokogiri', '~> 1.19.4' # HTML/XML parser
gem 'noticed'
gem 'odf-report', git: 'https://github.com/scinote-eln/odf-report', branch: 'rich-text-improvements' # Build report from odt template
gem 'oj'
gem 'rails_autolink', '~> 1.1', '>= 1.1.6'
gem 'rgl' # Graph framework for project diagram calculations
gem 'roo', '~> 2.10.0' # Spreadsheet parser
gem 'rotp'
gem 'rqrcode', '~> 2.0' # QR code generator
gem 'rubyzip', '>= 2.3.0' # will load new rubyzip version
gem 'silencer' # Silence certain Rails logs
gem 'turbolinks', '~> 5.2.0'
gem 'underscore-rails'
gem 'wicked_pdf'
gem 'zip-zip' # will load compatibility for old rubyzip API.

gem 'aws-actionmailer-ses', '~> 1'
gem 'aws-sdk-lambda'
gem 'aws-sdk-rails', '~> 5'
gem 'aws-sdk-s3'
gem 'delayed_job_active_record'
gem 'image_processing'
gem 'img2zpl', git: 'https://github.com/scinote-eln/img2zpl'
gem 'rufus-scheduler'

gem 'discard'

gem 'graphviz'

gem 'cssbundling-rails'
gem 'jsbundling-rails'
gem 'js-routes'

gem 'tailwindcss-rails', '~> 2.4'

gem 'base62' # Used for smart annotations
gem 'newrelic_rpm'
gem 'opentelemetry-exporter-otlp'
gem 'opentelemetry-instrumentation-pg'
gem 'opentelemetry-instrumentation-rails'
gem 'opentelemetry-propagator-xray'
gem 'opentelemetry-sdk'

# Permission helper Gem
gem 'canaid', git: 'https://github.com/scinote-eln/canaid'

group :development, :test do
  gem 'awesome_print'
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'brakeman', require: false
  gem 'bullet'
  gem 'byebug'
  gem 'database_cleaner'
  gem 'factory_bot_rails'
  gem 'faker' # Generate fake data
  gem 'figaro'
  gem 'listen'
  gem 'overcommit'
  gem 'parallel_tests'
  gem 'pry'
  gem 'pry-byebug'
  gem 'pry-rails'
  gem 'rails-controller-testing'
  gem 'rspec-rails'
  gem 'rubocop', require: false
  gem 'rubocop-performance'
  gem 'rubocop-rails'
  gem 'sdoc', '~> 1.0', group: :doc
  gem 'timecop'
end

group :test do
  gem 'capybara'
  gem 'capybara-email'
  gem 'cucumber-rails', require: false
  gem 'json_matchers'
  gem 'selenium-webdriver'
  gem 'shoulda-matchers'
  gem 'simplecov', require: false
  gem 'webmock'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i(mingw mswin x64_mingw jruby)

# Addons
#
# ⚠️ 停用记录 2026-10-07 —— 以下 5 个 addon 已从 Gemfile 摘除（代码保留在 addons/ 目录，随时可恢复）。
# 恢复方式：删掉本段注释，重新 bundle install 即可，无需改动任何业务代码。
# 停用原因：减少默认装载的 addon 面积，缩小 /workbench 列表类页面的干扰面与性能开销。
#
# 已验证（停用前核查，均为 0 命中 ⇒ 可安全移除）：
#   · 5 个 addon 之间无相互 gemspec 依赖
#   · 保留的 4 个 addon（addon_settings / access_control / eln_ui / workbench）不引用被禁 addon 的任何命名空间
#   · 宿主 app/ lib/ config/ 不引用 i18n addon 的 ControllerLocale / UserLocale / Scinote::I18n
#     ⇒ 停用 i18n 不会让宿主报 NameError，仅失去语言切换入口。
#
# gem 'scinote_i18n',           path: 'addons/i18n'              # 语言切换
# gem 'scinote_ai_protocols',   path: 'addons/ai_protocols'      # AI Protocol
# gem 'scinote_esignatures',    path: 'addons/esignatures'       # 电子签名
# gem 'scinote_project_insights', path: 'addons/project_insights' # 项目洞察
# gem 'scinote_ai_eln',         path: 'addons/ai_eln'            # AI ELN（本就暗挂载：AI_ELN_ENABLED=false）

gem 'scinote_addon_settings', path: 'addons/addon_settings'
gem 'scinote_access_control', path: 'addons/access_control'
gem 'scinote_eln_ui', path: 'addons/eln_ui'
gem 'scinote_workbench', path: 'addons/workbench'
