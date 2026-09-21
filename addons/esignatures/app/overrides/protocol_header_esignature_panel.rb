# frozen_string_literal: true

# Injects the electronic-signature panel into the protocol show header.
# deface lets us extend the core view without editing core app/ (addon-only
# change surface, per docs/development/addon-dev-workflow.md).
#
# `signature_panel_for` is a no-op (empty safe string) unless the current user
# holds the `can_sign_protocol_record?` permission, so dropping it in is safe on
# every render of this partial.
Deface::Override.new(
  virtual_path: 'protocols/header',
  name: 'esignatures_protocol_panel',
  insert_after: 'div.content-header',
  text: '<% if Scinote::Esignatures.enabled? %><%= signature_panel_for(@protocol) %><% end %>',
  disabled: false
)
