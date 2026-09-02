module Scinote
  module I18n
    LOCALES = %i[en zh-CN].freeze
    LANGUAGE_NAMES = {
      en: 'English',
      'zh-CN'.to_sym => '简体中文'
    }.freeze

    def self.available_locales
      LOCALES
    end

    def self.language_name(locale)
      LANGUAGE_NAMES.fetch(locale.to_sym, locale.to_s)
    end

    # 设置页卡片简介（参照 Label printers 的标题+描述风格）。
    def self.description
      'scinote_i18n.settings.description'
    end

    # 配置子页的详细说明。
    def self.detailed_help
      'scinote_i18n.settings.detailed_help'
    end

    # 国际化是实例级基础能力，必须常驻启用，不可被禁用。
    def self.disablable?
      false
    end
  end
end
