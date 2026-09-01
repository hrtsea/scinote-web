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
  end
end
