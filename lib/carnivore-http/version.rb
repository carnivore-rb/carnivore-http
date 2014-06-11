module Carnivore
  module Http
    # Custom version class
    class Version < Gem::Version
    end
    # Current library version
    VERSION = Version.new('0.1.6')
  end
end
