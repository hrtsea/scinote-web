# frozen_string_literal: true

# Legacy path. Zeitwerk expects app/permissions/ai_protocols.rb to define the
# top-level `AiProtocols` constant, so we only declare it here. The actual
# "Create with AI" permission rule is registered in
# app/permissions/scinote/ai_protocols/permissions.rb via
# Canaid::Permissions.register_for(Team).
module AiProtocols
end
