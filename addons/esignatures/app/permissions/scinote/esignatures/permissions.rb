# frozen_string_literal: true

module Scinote
  module Esignatures
    # `app/permissions` is an autoload path like any other `app/*` subdirectory,
    # so Zeitwerk expects this file to define a matching constant. The module is
    # intentionally empty: the actual rules are registered as canaid permissions
    # at the bottom of this file, which is what canaid consumes.
    module Permissions
    end
  end
end

# Signing authority follows the existing authorization model: you may
# electronically sign a record you are authorized to manage. Delegating to the
# core `manage` permissions keeps a single source of truth instead of a parallel
# rule set that could drift away from it.
#
# canaid forbids reusing one permission name across several object classes, so
# each signable type gets its own permission. `SignaturePolicy` dispatches on the
# record's class (STI-aware) and exposes the single `can_sign_record?` seam used
# by the controller and the view helper.
Canaid::Permissions.register_for(Protocol) do
  can :sign_protocol_record do |user, protocol|
    # A protocol lives either in the repository or inside a task; both count.
    can_manage_protocol_in_repository?(user, protocol) ||
      can_manage_protocol_in_module?(user, protocol)
  end
end

Canaid::Permissions.register_for(ResultBase) do
  can :sign_result_record do |user, result|
    can_manage_result?(user, result)
  end
end

Canaid::Permissions.register_for(Experiment) do
  can :sign_experiment_record do |user, experiment|
    can_manage_experiment?(user, experiment)
  end
end
