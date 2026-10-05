# frozen_string_literal: true

$:.push File.expand_path('../lib', __FILE__)

require 'scinote/workbench/version'

Gem::Specification.new do |s|
  s.name        = 'scinote_workbench'
  s.version     = Scinote::Workbench::VERSION
  s.authors     = ['SciNote ELN UI Team']
  s.email       = ['']
  s.homepage    = ''
  s.summary     = 'Role-aware workbench dashboard for SciNote (Vue3 prototype rebuild)'
  s.description = 'Homepage rendered per logged-in role against real SciNote data. ' \
                  'All counters are read live from the business database (no cached ' \
                  'snapshot); every clickable target is drilled into a real page, ' \
                  'never a self-drawn detail table.'
  s.license     = 'MPL-2.0'

  s.files = Dir['{app,config,lib}/**/*',
                'LICENSE.txt',
                'Rakefile',
                'README.md']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'rails', '>= 7.0'
end
