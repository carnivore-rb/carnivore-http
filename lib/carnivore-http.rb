require 'carnivore-http/version'
require 'carnivore'

Carnivore::Source.provide(:http, 'carnivore-http/http')
Carnivore::Source.provide(:http_endpoints, 'carnivore-http/http_endpoints')
