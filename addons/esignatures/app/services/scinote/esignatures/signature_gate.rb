# frozen_string_literal: true

module Scinote
  module Esignatures
    # Shared signature gate. Authorization is delegated to SignaturePolicy, which
    # evaluates the core canaid `can_manage_*` helpers with an explicit user.
    # Exposes a single `can_sign_record?(record)` usable from both controllers
    # and views (where `current_user` is available).
    module SignatureGate
      def can_sign_record?(record)
        Scinote::Esignatures::SignaturePolicy.permits?(current_user, record)
      end
    end
  end
end
