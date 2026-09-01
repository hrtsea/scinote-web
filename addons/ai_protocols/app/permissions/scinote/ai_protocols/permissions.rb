# frozen_string_literal: true

module Scinote
  module AiProtocols
    # `app/permissions` is an autoload path like any other `app/*` subdirectory,
    # so Zeitwerk expects this file to define a matching constant. The module is
    # intentionally empty: the actual rule is registered as a canaid permission
    # below, which is what canaid consumes.
    module Permissions
    end
  end
end

Canaid::Permissions.register_for(Team) do
  can :generate_protocol_with_ai do |user, team|
    team.present? && can_create_protocols_in_repository?(user, team)
  end
end
