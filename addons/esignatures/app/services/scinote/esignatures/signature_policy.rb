# frozen_string_literal: true

module Scinote
  module Esignatures
    # Decides whether a user may electronically sign a given record.
    #
    # Dispatches to the addon's own canaid permission for the record's type (see
    # app/permissions/scinote/esignatures/permissions.rb), which in turn delegates
    # to the core `manage` permission. Keeping this indirection means the signing
    # rule stays a first-class canaid permission (auditable, reusable) while
    # policies still have a single place to tighten.
    #
    # canaid exposes `can_<perm>?(user, obj)` through Canaid::Helpers::PermissionsHelper,
    # so we include it here and evaluate the permission with an explicit user.
    class SignaturePolicy
      include Canaid::Helpers::PermissionsHelper

      # Ordered: an STI subclass must be matched by its registered base class,
      # hence `is_a?` instead of an exact class lookup.
      SIGN_PERMISSION = [
        [Protocol, :can_sign_protocol_record?],
        [ResultBase, :can_sign_result_record?],
        [Experiment, :can_sign_experiment_record?]
      ].freeze

      def self.permits?(user, record)
        new(user, record).permits?
      end

      def initialize(user, record)
        @user = user
        @record = record
      end

      def permits?
        return false unless @user && @record

        permission = SIGN_PERMISSION.find { |klass, _| @record.is_a?(klass) }&.second
        return false unless permission

        public_send(permission, @user, @record).present?
      end
    end
  end
end
