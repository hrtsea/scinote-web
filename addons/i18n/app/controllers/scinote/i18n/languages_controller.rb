module Scinote
  module I18n
    class LanguagesController < ApplicationController
      # 允许未登录用户在登录页切换语言（通过 session 持久化）
      skip_before_action :authenticate_user!

      # POST /users/settings/locale { locale: 'zh-CN' }
      def update
        locale = params[:locale].to_s
        if Scinote::I18n.available_locales.map(&:to_s).include?(locale)
          persist_locale(locale)
          flash[:notice] = ::I18n.t('scinote_i18n.language_changed')
        else
          flash[:alert] = ::I18n.t('scinote_i18n.invalid_locale')
        end

        redirect_back fallback_location: '/'
      end

      private

      def persist_locale(locale)
        if respond_to?(:user_signed_in?) && user_signed_in?
          current_user.update(settings: current_user.settings.merge(locale: locale))
        else
          session[:locale] = locale
        end
      end
    end
  end
end
