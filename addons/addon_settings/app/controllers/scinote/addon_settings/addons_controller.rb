# frozen_string_literal: true

module Scinote
  module AddonSettings
    class AddonsController < ::ApplicationController
      before_action :set_breadcrumbs_items, only: %i(index)
      before_action :authorize_addon_admin!, only: %i(edit update)

      layout 'fluid'
      include ::AddonsHelper

      def index
        @label_printer_any = LabelPrinter.any?

        @user_agent = request.user_agent

        @addons = can_manage_addons? ? available_addon_names : []
      end

      # Per-addon configuration editor (sub-page). Instance admins only; renders
      # the enable toggle + schema-driven config fields for a single addon.
      def edit
        return head(:not_found) unless available_addon_names.include?(params[:name])

        @addon_name = params[:name]
        @addon_toggleable = AddonSetting.toggleable?(@addon_name)
        @setting = AddonSetting.for(@addon_name)
        @breadcrumbs_items = [
          { label: t('breadcrumbs.addons'), url: addons_path },
          { label: @addon_name.titleize, url: nil }
        ]
      end

      # Persist the enable/configuration of a single addon (instance-level).
      # Only instance administrators (see InstanceAdmin / :manage_addons) may call this.
      def update
        return head(:not_found) unless available_addon_names.include?(params[:name])

        setting = AddonSetting.for(params[:name])

        setting.enabled = if AddonSetting.toggleable?(params[:name])
                            ActiveModel::Type::Boolean.new.cast(params[:enabled])
                          else
                            true
                          end

        setting.configuration = AddonSetting.typed_configuration(
          params[:configuration], setting.name, existing: setting.configuration
        )

        setting.save!

        redirect_to addons_path,
                    notice: t('users.settings.account.addons.updated')
      rescue ActiveRecord::RecordInvalid, JSON::ParserError, AddonSetting::InvalidConfiguration
        redirect_to addons_path,
                    alert: t('users.settings.account.addons.update_error')
      end

      private

      def authorize_addon_admin!
        head :forbidden unless can_manage_addons?
      end

      # Names of the addons, derived from the single source of truth
      # `list_all_addons` (Rails::Engine reflection) instead of a raw
      # filesystem scan of `Rails.root/addons`. This keeps the managed
      # addon set aligned with canaid/permission discovery and prevents
      # listing unloaded "zombie" directories (which would spawn orphan
      # AddonSetting records). The engine module is reduced to its
      # underscore string name (Scinote::AddonSettings -> 'addon_settings')
      # to stay compatible with AddonSetting.for/enabled?/toggleable?.
      def available_addon_names
        list_all_addons
          .map { |addon| addon.to_s.split('::').last.underscore }
          .sort
      end

      def set_breadcrumbs_items
        @breadcrumbs_items = []
        @breadcrumbs_items.push(
          label: t('breadcrumbs.addons'),
          url: addons_path
        )
      end

      # Render helper for per-addon config schema fields lives in this addon's
      # own helper module (kept separate from the core AddonsHelper so the two
      # do not collide on the base `AddonsHelper` constant).
      helper Scinote::AddonSettings::AddonsHelper
    end
  end
end
