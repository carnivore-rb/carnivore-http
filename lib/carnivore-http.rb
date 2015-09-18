require 'carnivore-http/version'
require 'carnivore'
require 'multi_json'

module Carnivore
  # HTTP namespace
  module Http
    autoload :App, 'carnivore-http/app'
    autoload :PointBuilder, 'carnivore-http/point_builder'
    autoload :RetryDelivery, 'carnivore-http/retry_delivery'
  end

  class Source
    autoload :Http, 'carnivore-http/http'
    autoload :HttpSource, 'carnivore-http/http_source'
    autoload :HttpPaths, 'carnivore-http/http_paths'
    autoload :HttpEndpoints, 'carnivore-http/http_endpoints'
  end

  autoload :Utils, 'carnivore-http/utils'

  # Compat for old naming
  autoload :PointBuilder, 'carnivore-http/point_builder'
end

Carnivore::Source.provide(:http, 'carnivore-http/http')
Carnivore::Source.provide(:http_paths, 'carnivore-http/http_paths')
Carnivore::Source.provide(:http_endpoints, 'carnivore-http/http_endpoints')
