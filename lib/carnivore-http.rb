require 'carnivore-http/version'
require 'carnivore'
require 'multi_json'

module Carnivore
  # HTTP namespace
  module Http
    autoload :PointBuilder, 'carnivore-http/point_builder'
  end

  module Source
    autoload :Http, 'carnivore-http/http'
    autoload :HttpEndpoints, 'carnivore-http/http_endpoints'
  end

  autoload :Utils, 'carnivore-http/utils'

  # Compat for old naming
  autoload :PointBuilder, 'carnivore-http/point_builder'
end

Carnivore::Source.provide(:http, 'carnivore-http/http')
Carnivore::Source.provide(:http_endpoints, 'carnivore-http/http_endpoints')
