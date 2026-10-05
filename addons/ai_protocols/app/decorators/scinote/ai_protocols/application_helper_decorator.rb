# frozen_string_literal: true

# to_prepare 阶段（早于 eager load）尚未加载引擎 helpers 目录，
# 此处显式 require，避免 `uninitialized constant ... ProtocolGenerateHelper`。
require_relative '../../../helpers/scinote/ai_protocols/protocol_generate_helper'

# Exposes Scinote::AiProtocols::ProtocolGenerateHelper (and thus
# `can_generate_protocol_with_ai?`) to the host ApplicationHelper so core views
# such as `protocols/index` can render the AI create-button override without
# raising NoMethodError. Loaded by the engine's `to_prepare` block (see
# lib/scinote/ai_protocols/engine.rb), mirroring the esignatures addon.
module ApplicationHelper
  include Scinote::AiProtocols::ProtocolGenerateHelper
end
