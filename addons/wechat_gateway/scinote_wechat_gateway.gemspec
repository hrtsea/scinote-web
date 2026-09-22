$:.push File.expand_path('../lib', __FILE__)
require 'scinote/wechat_gateway/version'

Gem::Specification.new do |s|
  s.name        = 'scinote_wechat_gateway'
  s.version     = Scinote::WechatGateway::VERSION
  s.authors     = ['ELN Team']
  s.summary     = 'WeChat / WeCom to SciNote gateway addon'
  s.description = 'Receive WeChat/WeCom messages and write experiments/tasks into SciNote in-process.'
  s.license     = 'MPL-2.0'

  s.files = Dir['{app,config,db,lib}/**/*', 'LICENSE.txt', 'Rakefile', 'README.rdoc']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'rails', '~> 7.2'
  s.add_dependency 'deface', '~> 1.9'
  s.add_dependency 'nokogiri', '~> 1.19' # Robust XML parsing of WeCom callbacks (REXML mis-parses CDATA with / + =)
  s.add_dependency 'wechat' # Reuse Wechat::CorpApi (outbound only); callbacks use our own WecomCrypto (gem Cipher IV incompatible)
end
