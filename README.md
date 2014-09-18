# Carnivore HTTP

Provides HTTP `Carnivore::Source`

# Usage

## HTTP

```ruby
require 'carnivore'
require 'carnivore-http'

Carnivore.configure do
  source = Carnivore::Source.build(
    :type => :http,
    :args => {
      :port => 8080
    }
  )
end
```

## HTTP with configured end points

```ruby
require 'carnivore'
require 'carnivore-http'

Carnivore.configure do
  source = Carnivore::Source.build(
    :type => :http_endpoints,
    :args => {
      :auto_respond => false
    }
  )
end.start!
```

## Available options for `:args`

* `:bind` address to bind
* `:port` port to listen
* `:auto_respond` confirm request immediately
* `:ssl` ssl configuration
  * `:cert` path to cert file
  * `:key` path to key file
* `:authorization` access restrictors
  * `:allowed_origins` list of IP or IP ranges
  * `:htpasswd` htpasswd for authentication
  * `:credentials` username/password key pair for authentication
  * `:valid_on` 'any' match any restrictor, 'all' match all restrictors
* `:endpoint` specific uri to transmit (can include auth + path)
* `:method` HTTP method for transmission

# Info
* Carnivore: https://github.com/carnivore-rb/carnivore
* Repository: https://github.com/carnivore-rb/carnivore-http
* IRC: Freenode @ #carnivore
