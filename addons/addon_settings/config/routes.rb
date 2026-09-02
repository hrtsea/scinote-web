# frozen_string_literal: true

Scinote::AddonSettings::Engine.routes.draw do
  get 'users/settings/account/addons',
      to: 'users/settings/account/addons#index',
      as: :addons
  put 'users/settings/account/addons/:name',
      to: 'users/settings/account/addons#update',
      as: :update_addon
end
