# frozen_string_literal: true

$:.push File.expand_path('../lib', __FILE__)

require 'scinote/access_control/version'

Gem::Specification.new do |s|
  s.name        = 'scinote_access_control'
  s.version     = Scinote::AccessControl::VERSION
  s.authors     = ['SciNote AccessControl Team']
  s.email       = ['']
  s.homepage    = ''
  s.summary     = 'Access control visibility addon for SciNote'
  s.description = 'Auto-applies visibility / assignment policy when ' \
                 'Experiment/MyModule are created. Plug into creator so they ' \
                 'always get manage-level access to their own objects.'
  s.license     = 'MPL-2.0'

  s.files = Dir['{app,config,lib}/**/*',
                'LICENSE.txt',
                'Rakefile',
                'README.md']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'rails', '>= 7.0'
end