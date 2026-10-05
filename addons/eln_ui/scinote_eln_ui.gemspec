# frozen_string_literal: true

$:.push File.expand_path('../lib', __FILE__)

require 'scinote/eln_ui/version'

Gem::Specification.new do |s|
  s.name        = 'scinote_eln_ui'
  s.version     = Scinote::ElnUi::VERSION
  s.authors     = ['SciNote ELN UI Team']
  s.email       = ['']
  s.homepage    = ''
  s.summary     = 'Vue3 prototype-driven ELN UI pages for SciNote'
  s.description = 'Renders ELN pages rebuilt from the Vue3 prototype ' \
                  '(ELN系统-Vue3) against real SciNote data. Vue mounts only the ' \
                  'content area; host layout / sidebar stay native.'
  s.license     = 'MPL-2.0'

  s.files = Dir['{app,config,lib}/**/*',
                'LICENSE.txt',
                'Rakefile',
                'README.md']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'rails', '>= 7.0'
end
