# frozen_string_literal: true

$LOAD_PATH.push(File.expand_path('lib', __dir__))

# Maintain this gem's version:
require 'scinote/addon_settings/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'scinote_addon_settings'
  s.version     = Scinote::AddonSettings::VERSION
  s.authors     = %w(SciNote)
  s.summary     = 'SciNote add-ons settings page addon'
  s.description = 'Renders the instance-level add-on management UI (enable/configure each addon) as a self-contained addon.'
  s.license     = 'MIT'
  s.required_ruby_version = '>= 3.1'

  s.files = Dir['{app,config,db,lib}/**/*', 'LICENSE.txt', 'Rakefile', 'VERSION']
  s.require_paths = %w(lib)

  # No hard dependency on Rails version - runs inside the host application
  s.metadata['rubygems_mfa_required'] = 'true'
end
