# frozen_string_literal: true

Scinote::AddonSettings::Engine.routes.draw do
  get 'users/settings/account/addons',
      to: 'addons#index',
      as: :addons
  get 'users/settings/account/addons/:name',
      to: 'addons#edit',
      as: :edit_addon
  put 'users/settings/account/addons/:name',
      to: 'addons#update',
      as: :update_addon
end
