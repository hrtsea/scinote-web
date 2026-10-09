# frozen_string_literal: true

# 注入 AI 协议解析弹窗的挂载点（#aiParserContainer）+ 弹窗 pack。
#
# 形态逐字对齐官方（my.scinote.net/modules/:id/protocols 实测反抽，
# 见 规格/ELN系统/调研/官方AI协议解析-源码级反抽.md §9）：
#   · 挂载点位于 .sci--layout-content 内，id = aiParserContainer；
#   · 宿主入口（app/javascript/vue/protocol/protocolOptions.vue 与
#     app/javascript/vue/protocols/table.vue）已存在，点击时
#     `document.querySelector('#importWithAI').click()` —— 由弹窗组件渲染该隐藏触发器。
#   ⇒ 本 override 只补「官方有、本仓缺」的挂载点与资源，不改任何核心 app/ 文件。
#
# 配置下发方式（与官方一致）：
#   · 开关/数值类 → <ai-parser-container> 的 kebab-case 组件属性（in-DOM 模板）
#   · i18n 字典 → data-i18n-strings 属性（服务端 ERB t() 注入 JSON，规避 CSP 内联脚本）
#
# 付费墙/授权：本仓无套餐概念，decorator 强制 Protocol.ai_parser_enabled? = true（见
# app/decorators/.../protocol_decorator.rb），故 ai-parser-enabled 恒为 "true"，
# 直接渲染导入弹窗；promoType 仅在未授权分支使用。
#
# 🔴🔴 铁律：本 heredoc **绝不能 .squish**。squish 会把整段 ERB 压成单行，导致：
#   ① heredoc 内以换行分隔的 Ruby 语句（ai_keys = … / i18n = … / i18n_json = …）
#      被并成「一条非法语句」→ 语法错；
#   ② 若出现 `#` 行注释，压行后 `#` 会吞掉其后所有代码。
#   两者都会使 layout 编译失败 → ActionView::SyntaxErrorInTemplate → 整站所有页面
#   （含未登录 /users/sign_in）500。保留换行（<<~HTML 自带去缩进）即天然正确；
#   说明性注释一律写在 heredoc 之外。
# 🔴🔴 protocols 列表/详情页都走 `layouts/fluid`（见 protocols_controller.rb:86
# `layout 'fluid'`），而我的入口触发器 `#importWithAI` 由本容器内的 Vue 组件渲染，
# 故**必须同时挂 application + fluid 两个 layout**，否则详情页（fluid）无挂载点 →
# Options 下拉的「Create with AI」点了无反应。两个 layout 都有 `div.sci--layout-content`。
AI_PARSER_HTML = <<~HTML
    <% if user_signed_in? %>
      <%
        ai_keys = {
          'modal.title' => 'ai_parser.modal.title',
          'modal.how_to_use_title' => 'ai_parser.modal.how_to_use_title',
          'modal.description' => 'ai_parser.modal.description',
          'modal.disclaimer' => 'ai_parser.modal.disclaimer',
          'modal.prompt_only' => 'ai_parser.modal.prompt_only',
          'modal.file_upload' => 'ai_parser.modal.file_upload',
          'modal.file_import' => 'ai_parser.modal.file_import',
          'modal.upload' => 'ai_parser.modal.upload',
          'modal.generate' => 'ai_parser.modal.generate',
          'modal.processing' => 'ai_parser.modal.processing',
          'modal.prompt_label' => 'ai_parser.modal.prompt_label',
          'modal.supporting_text' => 'ai_parser.modal.supporting_text',
          'modal.prompt_placeholder_1' => 'ai_parser.modal.prompt_placeholder_1',
          'modal.prompt_placeholder_2_text' => 'ai_parser.modal.prompt_placeholder_2_text',
          'modal.prompt_placeholder_2_file' => 'ai_parser.modal.prompt_placeholder_2_file',
          'modal.limit_reached' => 'ai_parser.modal.limit_reached',
          'modal.create_protocol' => 'ai_parser.modal.create_protocol',
          'modal.create_template' => 'ai_parser.modal.create_template',
          'modal.protocol_preview' => 'ai_parser.modal.protocol_preview',
          'modal.preview_description' => 'ai_parser.modal.preview_description',
          'modal.step' => 'ai_parser.modal.step',
          'modal.protocol_created_successfully' => 'ai_parser.modal.protocol_created_successfully',
          'modal.document_error' => 'ai_parser.modal.document_error',
          'modal.invalid_protocol_error' => 'ai_parser.modal.invalid_protocol_error',
          'modal.information_blocks.select_option.label' => 'ai_parser.modal.information_blocks.select_option.label',
          'modal.information_blocks.select_option.description' => 'ai_parser.modal.information_blocks.select_option.description',
          'modal.information_blocks.write_prompt.label' => 'ai_parser.modal.information_blocks.write_prompt.label',
          'modal.information_blocks.write_prompt.description' => 'ai_parser.modal.information_blocks.write_prompt.description',
          'modal.information_blocks.generate.label' => 'ai_parser.modal.information_blocks.generate.label',
          'modal.information_blocks.generate.description' => 'ai_parser.modal.information_blocks.generate.description',
          'modal.information_blocks.review.label' => 'ai_parser.modal.information_blocks.review.label',
          'modal.information_blocks.review.description' => 'ai_parser.modal.information_blocks.review.description',
          'modal.information_blocks.create_template.label' => 'ai_parser.modal.information_blocks.create_template.label',
          'modal.information_blocks.create_template.description' => 'ai_parser.modal.information_blocks.create_template.description',
          'confirmation_modal.title' => 'ai_parser.confirmation_modal.title',
          'confirmation_modal.description' => 'ai_parser.confirmation_modal.description',
          'confirmation_modal.description_load_html' => 'ai_parser.confirmation_modal.description_load_html',
          'confirmation_modal.option_merge_html' => 'ai_parser.confirmation_modal.option_merge_html',
          'confirmation_modal.option_replace_html' => 'ai_parser.confirmation_modal.option_replace_html',
          'confirmation_modal.confirmation_description_html' => 'ai_parser.confirmation_modal.confirmation_description_html',
          'confirmation_modal.load' => 'ai_parser.confirmation_modal.load',
          'promo_modal.title_free' => 'ai_parser.promo_modal.title_free',
          'promo_modal.description_free' => 'ai_parser.promo_modal.description_free',
          'promo_modal.title_premium' => 'ai_parser.promo_modal.title_premium',
          'promo_modal.description_premium' => 'ai_parser.promo_modal.description_premium',
          'promo_modal.learn_more' => 'ai_parser.promo_modal.learn_more',
          'promo_modal.upgrade' => 'ai_parser.promo_modal.upgrade'
        }
        i18n = ai_keys.values.each_with_object({}) { |k, h| h[k] = t(k) }
        i18n['general.cancel'] = t('general.cancel')
        i18n['general.close'] = t('general.close')
        i18n['general.error'] = t('general.error')
        i18n['attachments.new.general_error'] = t('attachments.new.general_error')
        i18n['repositories.import_records.dragAndDropUpload.fileTooLargeError'] = t('repositories.import_records.dragAndDropUpload.fileTooLargeError')
        i18n_json = i18n.to_json.gsub("'", "&#39;")
      %>
      <div id="aiParserContainer">
        <ai-parser-container
          file-limit-mb="<%= Rails.configuration.x.file_max_size_mb %>"
          ai-parser-promo="free"
          ai-parser-enabled="<%= Protocol.ai_parser_enabled? %>"
          upgrade-url="https://share.hsforms.com/19M8ZRMWBTrqZDXmJX8G28Q2aj9a"
          learn-more-url="https://knowledgebase.scinote.net/en/knowledge/ai-protocol-parser"
          data-i18n-strings='<%= i18n_json %>'>
        </ai-parser-container>
      </div>
      <%= stylesheet_link_tag 'ai_protocol_parser' %>
      <%= javascript_include_tag 'ai_protocol_parser' %>
    <% end %>
  HTML

%w[layouts/application layouts/fluid].each do |vp|
  Deface::Override.new(
    virtual_path: vp,
    name: "ai_protocols_inject_parser_container_#{vp.tr('/', '_')}",
    insert_bottom: 'div.sci--layout-content',
    text: AI_PARSER_HTML
  )
end
