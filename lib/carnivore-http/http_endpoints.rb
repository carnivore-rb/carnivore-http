require 'carnivore-http/http'
require 'carnivore-http/point_builder'

module Carnivore
  class Source

    # Carnivore HTTP end points source
    class HttpEndpoints < Http

      class << self

        # Register endpoint
        #
        # @param args [Hash]
        # @option args [String] :name
        # @option args [String] :base_path
        def register(args={})
          args = Hash[*(
              args.map do |k,v|
                [k.to_sym, v]
              end.flatten
          )]
          builder = {:name => args[:name], :base_path => args[:base_path]}
          if(res = builder.find_all{|x,y| y.nil})
            raise ArgumentError.new("Missing required argument! (#{res.map(&:first).join(',')})")
          end
          builders[builder[:name].to_sym] = builder[:base_path]
          self
        end

        # @return [Hash] point builders registered
        def builders
          @point_builders ||= {}
        end

        # Load the named builder
        #
        # @param name [String] name of builder
        # @return [self]
        def load_builder(name)
          if(builders[name.to_sym])
            require File.join(builders[name.to_sym], name)
          else
            raise NameError.new("Requested end point builder not found (#{name})")
          end
          self
        end

        # Setup the builders
        #
        # @return [TrueClass]
        def setup!
          only = Carnivore::Config.get(:http_endpoints, :only)
          except = Carnivore::Config.get(:http_endpoints, :except)
          # NOTE: Except has higher precedence than only
          builders.keys.each do |name|
            next if only && !only.include?(name.to_s)
            next if except && except.include?(name.to_s)
            load_builder(name)
          end
          true
        end

      end

      # @return [Hash] point builders
      attr_reader :points

      # Setup the registered endpoints
      #
      # @param args [Hash]
      # @option args [String, Symbol] :config_key
      def setup(args={})
        super
        @conf_key = (args[:config_key] || :http_endpoints).to_sym
        set_points
      end

      # Always auto start
      def auto_process?
        true
      end

      # Process requests
      def process(*process_args)
        unless(processing)
          @processing = true
          srv = Reel::Server::HTTP.supervise(args[:bind], args[:port]) do |con|
            con.each_request do |req|
              begin
                msg = build_message(con, req)
                unless(@points.deliver(msg))
                  warn "No match found for request: #{msg}"
                  req.respond(:ok, 'So long, and thanks for all the fish!')
                end
              rescue => e
                error "Failed to process message: #{e.class} - #{e}"
                debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
                req.respond(:bad_request, 'Failed to process request')
              end
            end
          end
          true
        else
          false
        end
      end

      # Build the endpoints and set
      #
      # @return [self]
      def set_points
        @points = PointBuilder.new(
          :only => Carnivore::Config.get(@conf_key, :only),
          :except => Carnivore::Config.get(@conf_key, :except)
        )
        self
      end
    end
  end
end
