# frozen_string_literal: true

$:.push File.expand_path('../lib', __FILE__)

require 'scinote/ai_eln/version'

Gem::Specification.new do |s|
  s.name        = 'scinote_ai_eln'
  s.version     = Scinote::AiEln::VERSION
  s.authors     = ['SciNote AI-ELN Team']
  s.email       = ['']
  s.homepage    = ''
  s.summary     = 'AI assistance addon for SciNote, zero-intrusion Rails Engine'
  s.description = 'Mountable addon injecting AI features (summary, parsing, ' \
                 'semantic search, audit) into SciNote without touching core code.'
  s.license     = 'MPL-2.0'

  s.files = Dir['{app,config,db,lib}/**/*',
                'LICENSE.txt',
                'Rakefile',
                'README.md']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'rails', '>= 7.0'
  s.add_dependency 'net-http'
end
