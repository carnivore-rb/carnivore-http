require 'carnivore-http/http'
require 'carnivore-http/point_builder'

module Carnivore
  class Source
    class HttpEndpoints < Http

      class << self

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

        def builders
          @point_builders ||= {}
        end

        def load_builder(name)
          if(builders[name.to_sym])
            require File.join(builders[name.to_sym], name)
          else
            raise NameError.new("Requested end point builder not found (#{name})")
          end
          self
        end

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

      attr_reader :points

      def setup(args={})
        super
        @conf_key = (args[:config_key] || :http_endpoints).to_sym
        set_points
      end

      def connect
        async.process
      end

      def process(*process_args)
        srv = Reel::Server.supervise(args[:bind], args[:port]) do |con|
          con.each_request do |req|
            begin
              msg = format(
                :request => req,
                :body => req.body.to_s,
                :connection => con,
                :query => parse_query_string(req.query_string).merge(parse_query_string(req.body.to_s))
              )
              unless(@points.deliver(msg))
                con.respond(:ok, 'So long, and thanks for all the fish!')
              end
            rescue => e
              error "Failed to process message: #{e.class} - #{e}"
              debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
              con.respond(:bad_request, 'Failed to process request')
            end
          end
        end
      end

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
