# frozen_string_literal: true

# Injects Scinote::Esignatures::SignatureHelper into the host ApplicationHelper
# so every core view (protocol / result / experiment) can call
# `signature_panel_for(record)` without modifying core code. Loaded by the
# engine's `to_prepare` block (see lib/scinote/esignatures/engine.rb).
module ApplicationHelper
  include Scinote::Esignatures::SignatureHelper
end
