# frozen_string_literal: true

# Inject a "Create with AI" entry button into the protocol templates library
# page (host view `protocols/index`). The override is surgical (deface) so it
# survives core upgrades and never edits app/ directly.
#
# Visibility is gated by the same two conditions the standalone flow enforces:
#   * the AI parser feature flag is on (Protocol.ai_parser_enabled?)
#   * the current user may create protocols in the current team
#     (can_generate_protocol_with_ai?, which itself delegates to
#      can_create_protocols_in_repository?)
#
# The link points at the addon's own new-action, mounted at '/ai_protocols/new'.
Deface::Override.new(
  virtual_path: 'protocols/index',
  name: 'ai_protocols_inject_create_button',
  insert_bottom: 'div.title-row',
  text: <<~HTML.squish
    <% if Protocol.ai_parser_enabled? &&
          can_generate_protocol_with_ai?(current_user, current_team) %>
      <%= link_to t('scinote_ai_protocols.create_with_ai'),
                  '/ai_protocols/new',
                  class: 'btn btn-primary pull-right',
                  id: 'createProtocolWithAi',
                  data: { e2e: 'e2e-BT-createProtocolWithAi' } %>
    <% end %>
  HTML
)
