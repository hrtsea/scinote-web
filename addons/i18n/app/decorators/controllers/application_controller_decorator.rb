# frozen_string_literal: true

# Zero-intrusion locale resolution for the whole application.
# Priority: current_user.settings[:locale] -> session -> Accept-Language -> en
module Scinote
  module I18n
    module ControllerLocale
      extend ActiveSupport::Concern

      included do
        before_action :set_locale
      end

      private

      def set_locale
        ::I18n.locale = resolved_locale
        # Expose the active locale to the frontend (read by scinote/i18n/application.js)
        cookies[:scinote_locale] = { value: ::I18n.locale.to_s, path: '/' }
      end

      def resolved_locale
        locale = current_user_locale
        locale ||= session[:locale]
        locale ||= locale_from_accept_language
        locale = locale.to_s.to_sym
        return locale if Scinote::I18n.available_locales.include?(locale)

        ::I18n.default_locale
      end

      def current_user_locale
        return nil unless respond_to?(:user_signed_in?) && user_signed_in?

        current_user.settings[:locale].presence
      end

      def locale_from_accept_language
        header = request.env['HTTP_ACCEPT_LANGUAGE'].to_s
        return nil if header.blank?

        lang = header.split(',').first.to_s.strip.split(';').first.to_s
        return nil if lang.blank?

        normalize_locale(lang)
      end

      def normalize_locale(lang)
        case lang.downcase
        when /\Azh/
          :'zh-CN'
        else
          :en
        end
      end
    end
  end
end

ApplicationController.include(Scinote::I18n::ControllerLocale)
