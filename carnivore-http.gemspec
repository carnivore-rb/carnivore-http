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
  s.add_runtime_dependency 'carnivore', '>= 1.0.0', '< 2.0'
  s.add_runtime_dependency 'puma', '~> 2.13.4'
  s.add_runtime_dependency 'rack', '~> 1.6.4'
  s.add_runtime_dependency 'blockenspiel', '~> 0.5.0'
  s.add_runtime_dependency 'htauth', '~> 2.0.0'
  s.add_development_dependency 'http'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'pry'
  s.files = Dir['lib/**/*'] + %w(carnivore-http.gemspec README.md CHANGELOG.md)
end
