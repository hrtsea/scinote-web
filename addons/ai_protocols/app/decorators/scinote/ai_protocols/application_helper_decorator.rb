# frozen_string_literal: true

# Exposes Scinote::AiProtocols::ProtocolGenerateHelper (and thus
# `can_generate_protocol_with_ai?`) to the host ApplicationHelper so core views
# such as `protocols/index` can render the AI create-button override without
# raising NoMethodError. Loaded by the engine's `to_prepare` block (see
# lib/scinote/ai_protocols/engine.rb), mirroring the esignatures addon.
module ApplicationHelper
  include Scinote::AiProtocols::ProtocolGenerateHelper
end
