# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'scinote/project_insights/version'

Gem::Specification.new do |s|
  s.name        = 'scinote_project_insights'
  s.version     = Scinote::ProjectInsights::VERSION
  s.authors     = %w(SciNote)
  s.summary     = 'SciNote Project Insights dashboard addon'
  s.description = 'Adds a standalone Project Insights page with status, workload, bottlenecks and due-date widgets.'
  s.license     = 'MIT'
  s.required_ruby_version = '>= 3.1'

  s.files = Dir['{app,config,db,lib}/**/*', 'LICENSE.txt', 'Rakefile', 'VERSION']
  s.require_paths = %w(lib)
  s.metadata['rubygems_mfa_required'] = 'true'
end
