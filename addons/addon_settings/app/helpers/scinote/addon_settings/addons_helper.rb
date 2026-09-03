# frozen_string_literal: true

module Scinote
  module AddonSettings
    module AddonsHelper
      # 渲染某个 addon 配置字段（label + 控件 + 帮助文本），按 schema 的 type 分派。
      # 控件命名 configuration[key]，由核心 AddonsController#cast_configuration 类型化收集。
      # disabled: 当 addon 关闭时为 true，禁用该字段（防止在禁用态误配）。
      def render_addon_config_field(field, setting, disabled: false)
        key = field[:key].to_s
        type = field[:type].to_s
        value = setting.config_value(key)
        value = field[:default] if value.nil? && field.key?(:default)

        field_id = "configuration_#{key}"
        label_text = t(field[:label])
        help_text = field[:help] ? t(field[:help]) : nil

        tag.div(class: 'addon-config-field flex flex-col gap-1 mt-1') do
          safe_join([
            label_tag(field_id, label_text, class: 'text-sn-black font-medium'),
            render_addon_config_input(field_id, key, type, value, field, disabled: disabled),
            # secret 字段已存值时给出"已设置"指示（不回显值本身）。
            (if type == 'secret' && value.present?
               tag.span(t('users.settings.account.addons.config_secret_set'),
                        class: 'text-sn-dark-grey text-xs')
             else
               nil
             end),
            (help_text ? tag.p(help_text, class: 'text-sn-dark-grey text-xs mt-0 mb-0') : nil)
          ].compact)
        end
      end

      def render_addon_config_input(field_id, key, type, value, field, disabled: false)
        name = "configuration[#{key}]"
        case type
        when 'boolean'
          check_box_tag(name, '1', value, id: field_id, class: 'm-2', disabled: disabled)
        when 'secret'
          # 不回显已存密钥；留空则保留原值（见 cast_configuration 的 secret 分支）。
          password_field_tag(name, '', id: field_id, class: 'form-control',
                             placeholder: field[:placeholder].to_s, autocomplete: 'new-password', disabled: disabled)
        when 'integer'
          number_field_tag(name, value, id: field_id, class: 'form-control',
                           min: 0, placeholder: field[:placeholder].to_s, disabled: disabled)
        when 'text'
          text_area_tag(name, value, id: field_id, rows: 3, class: 'form-control', disabled: disabled)
        when 'select'
          options = (field[:options] || []).map { |o| [t(o[:label]), o[:value]] }
          select_tag(name, options_for_select(options, value), id: field_id, class: 'form-control', disabled: disabled)
        else
          text_field_tag(name, value, id: field_id, class: 'form-control',
                         placeholder: field[:placeholder].to_s, disabled: disabled)
        end
      end
    end
  end
end
