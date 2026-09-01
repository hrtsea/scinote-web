# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'scinote/esignatures/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'scinote_esignatures'
  s.version     = Scinote::Esignatures::VERSION
  s.authors     = %w(SciNote)
  s.summary     = 'SciNote 21 CFR Part 11 electronic signatures addon'
  s.description = 'Append-only, hash-chained electronic signatures bound to ' \
                  'protocols/results/experiments for regulatory compliance.'
  s.license     = 'MIT'
  s.required_ruby_version = '>= 3.1'

  s.files = Dir['{app,config,db,lib}/**/*', 'LICENSE.txt', 'Rakefile', 'VERSION']
  s.require_paths = %w(lib)

  # No hard dependency on Rails version - runs inside the host application
  s.metadata['rubygems_mfa_required'] = 'true'
end
