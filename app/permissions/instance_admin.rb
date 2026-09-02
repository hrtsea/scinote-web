# frozen_string_literal: true

# Instance-level administrators: the only users permitted to manage global addon
# enable/configuration. The list lives in ApplicationSettings (key
# `instance_admin_user_ids`); when unset it defaults to the seeded admin
# (user id 1, i.e. admin@scinote.net).
#
# Defined here (under app/permissions) because this file is loaded by the canaid
# railtie during boot, so InstanceAdmin is brought into life by this file and the
# canaid :manage_addons permission can be registered alongside it.
module InstanceAdmin
  DEFAULT_ADMIN_IDS = [1].freeze

  def self.admin_ids
    ids = ApplicationSettings.instance.values['instance_admin_user_ids']
    Array(ids).map(&:to_i).presence || DEFAULT_ADMIN_IDS
  end

  def self.admin?(user)
    return false if user.nil?

    admin_ids.include?(user.id)
  end

  Canaid::Permissions.register_generic do
    # Instance-level administration of global addon enable/configuration.
    can :manage_addons do |user|
      InstanceAdmin.admin?(user)
    end
  end
end
