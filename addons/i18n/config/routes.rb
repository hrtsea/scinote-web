Scinote::I18n::Engine.routes.draw do
  post '/users/settings/locale', to: 'languages#update', as: :user_locale
end
