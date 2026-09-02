# frozen_string_literal: true

module Scinote
  module AiProtocols
    # View-facing seam mirroring the esignatures addon's pattern.
    #
    # `can_generate_protocol_with_ai?` is registered with canaid in
    # app/permissions/.../permissions.rb, but canaid only injects permissions
    # registered by the *host* app into the view helper chain during boot.
    # Permissions an addon registers later (in the engine's load phase) are NOT
    # re-injected as view helpers, so calling `can_generate_protocol_with_ai?`
    # from a core view (e.g. the `protocols/index` AI create-button override)
    # raises NoMethodError and blanks the whole page.
    #
    # Defining it explicitly here and mixing it into ApplicationHelper via the
    # engine's `to_prepare` decorator makes the method reliably available in
    # every core view. It delegates to `can_create_protocols_in_repository?`,
    # which the host app already exposes to views.
    module ProtocolGenerateHelper
      def can_generate_protocol_with_ai?(user, team)
        team.present? && can_create_protocols_in_repository?(team)
      end
    end
  end
end
