# frozen_string_literal: true

# to_prepare 阶段（早于 eager load）尚未加载引擎 helpers 目录，
# 此处显式 require，避免 `uninitialized constant ... SignatureHelper`。
require_relative '../../../helpers/scinote/esignatures/signature_helper'

# Injects Scinote::Esignatures::SignatureHelper into the host ApplicationHelper
# so every core view (protocol / result / experiment) can call
# `signature_panel_for(record)` without modifying core code. Loaded by the
# engine's `to_prepare` block (see lib/scinote/esignatures/engine.rb).
module ApplicationHelper
  include Scinote::Esignatures::SignatureHelper
end
