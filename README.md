# Carnivore HTTP

Provides HTTP `Carnivore::Source`

# Usage

## HTTP

```ruby
require 'carnivore'
require 'carnivore-http'

Carnivore.configure do
  source = Carnivore::Source.build(
    :type => :http, :args => {:port => 8080}
  )
end
```

## HTTP with configured end points

```ruby
require 'carnivore'
require 'carnivore-http'

Carnivore.configure do
  source = Carnivore::Source.build(
    :type => :http_endpoints, :args => {:auto_respond => false}
  )
end.start!
```

# Info
* Carnivore: https://github.com/heavywater/carnivore
* Repository: https://github.com/heavywater/carnivore-http
* IRC: Freenode @ #heavywater
