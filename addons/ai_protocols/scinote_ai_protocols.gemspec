# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

require 'scinote/ai_protocols/version'

Gem::Specification.new do |spec|
  spec.name        = 'scinote_ai_protocols'
  spec.version     = Scinote::AiProtocols::VERSION
  spec.authors     = %w[SciNote]
  spec.email       = ['dev@example.com']

  spec.summary     = 'AI protocol generation addon for SciNote'
  spec.description = 'Generate structured protocols from text/PDF via an OpenAI-compatible LLM.'
  spec.files       = Dir['lib/**/*', 'app/**/*', 'config/**/*']
  spec.require_paths = %w[lib]

  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.required_ruby_version = '>= 3.1'

  spec.add_dependency 'rails', '>= 6.0'
end
