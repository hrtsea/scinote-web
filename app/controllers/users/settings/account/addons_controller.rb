# frozen_string_literal: true

module Users
  module Settings
    module Account
      class AddonsController < ApplicationController
        before_action :set_breadcrumbs_items, only: %i(index)
        before_action :authorize_addon_admin!, only: %i(update)
        layout 'fluid'

        def index
          @label_printer_any = LabelPrinter.any?
          @user_agent = request.user_agent
          @addons = can_manage_addons? ? available_addon_names : []
        end

        # Persist the enable/configuration of a single addon (instance-level).
        # Only instance administrators (see InstanceAdmin / :manage_addons) may call this.
        def update
          setting = AddonSetting.for(params[:name])
          setting.enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled]) || false
          setting.configuration = cast_configuration(params[:name], params[:configuration])
          setting.save!
          redirect_to addons_path,
                      notice: t('users.settings.account.addons.updated')
        rescue ActiveRecord::RecordInvalid, JSON::ParserError, ArgumentError
          redirect_to addons_path,
                      alert: t('users.settings.account.addons.update_error')
        end

        private

        def authorize_addon_admin!
          render_403 unless can_manage_addons?
        end

        # 把表单提交的 configuration 转换为类型化 Hash 存入 JSONB。
        # 兼容旧契约：仍接受裸 JSON 字符串（整体原样存储）。
        # 新契约：表单按 schema 字段提交 configuration[key]=value，据字段类型转换。
        def cast_configuration(name, raw)
          return {} if raw.nil?
          return JSON.parse(raw) if raw.is_a?(String)

          raw_hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
          schema = AddonSetting.config_schema_for(name)
          config = AddonSetting.for(name).configuration || {}
          schema.each do |field|
            key = field[:key].to_s
            type = field[:type].to_s
            if type == 'boolean'
              # 未勾选时表单不提交该键，按 false 处理（可关闭）。
              config[key] = ActiveModel::Type::Boolean.new.cast(raw_hash[key])
            else
              next unless raw_hash.key?(key)

              config[key] = coerce_config_value(type, raw_hash[key], config[key])
            end
          end
          validate_configuration!(schema, config)
          config
        end

        # 字段级校验：integer 字段若提交负值则非法，阻止写入（必填/类型由 schema 约束）。
        def validate_configuration!(schema, config)
          schema.each do |field|
            next unless field[:type].to_s == 'integer'

            value = config[field[:key].to_s]
            next unless value.is_a?(Integer)

            raise ArgumentError, "Invalid value for #{field[:key]}: must be >= 0" if value < 0
          end
        end

        def coerce_config_value(type, value, existing)
          case type
          when 'integer'
            value.present? ? value.to_i : nil
          when 'secret'
            (value.presence || existing)
          else
            value.to_s
          end
        end

        # Names of the addons shipped under Rails.root/addons, used to render the
        # management UI. Each maps 1:1 to an AddonSetting name.
        def available_addon_names
          addons_dir = Rails.root.join('addons')
          return [] unless addons_dir.directory?

          addons_dir.children
                    .select(&:directory?)
                    .map { |entry| entry.basename.to_s }
                    .sort
        end

        def set_breadcrumbs_items
          @breadcrumbs_items = []
          @breadcrumbs_items.push({
                                    label: t('breadcrumbs.addons'),
                                    url: addons_path
                                  })
        end
      end
    end
  end
end
