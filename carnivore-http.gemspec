$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib/'
require 'carnivore-http/version'
Gem::Specification.new do |s|
  s.name = 'carnivore-http'
  s.version = Carnivore::Http::VERSION.version
  s.summary = 'Message processing helper'
  s.author = 'Chris Roberts'
  s.email = 'chrisroberts.code@gmail.com'
  s.homepage = 'https://github.com/carnivore-rb/carnivore-http'
  s.description = 'Carnivore HTTP source'
  s.license = 'Apache 2.0'
  s.require_path = 'lib'
  s.add_dependency 'carnivore', '>= 0.1.8'
  s.add_dependency 'reel', '~> 0.5.0'
  s.add_dependency 'blockenspiel'
  s.files = Dir['**/*']
end
