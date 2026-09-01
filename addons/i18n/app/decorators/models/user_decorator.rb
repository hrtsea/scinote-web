# frozen_string_literal: true

# Zero-intrusion User extension: adds `locale` to the existing settings hash
module Scinote
  module I18n
    module UserLocale
      extend ActiveSupport::Concern

      included do
        store_accessor :settings, :locale

        validate :locale_is_available

        private

        def locale_is_available
          return if locale.blank? ||
                    Scinote::I18n.available_locales.map(&:to_s).include?(locale.to_s)

          errors.add(:locale, :inclusion)
        end
      end
    end
  end
end

User.include(Scinote::I18n::UserLocale)
