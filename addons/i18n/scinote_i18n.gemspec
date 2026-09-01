$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'scinote/i18n/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'scinote_i18n'
  s.version     = Scinote::I18n::VERSION
  s.authors     = ['SciNote']
  s.summary     = 'SciNote multi-language (i18n) addon'
  s.description = 'Adds locale switching (user -> browser -> en) and translation files to SciNote.'
  s.license     = 'MIT'

  s.files = Dir['{app,config,db,lib}/**/*', 'LICENSE.txt', 'Rakefile', 'VERSION']
  s.require_paths = ['lib']

  # No hard dependency on Rails version - runs inside the host application
end
