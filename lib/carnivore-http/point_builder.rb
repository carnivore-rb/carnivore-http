require 'blockenspiel'
require 'singleton'
require 'carnivore/utils'
require 'celluloid'

module Carnivore
  class PointBuilder

    class Endpoint

      include Celluloid
      include Carnivore::Utils::Params
      include Carnivore::Utils::Logging

      attr_reader :endpoint, :type

      def initialize(type, endpoint, block)
        @endpoint = endpoint
        @type = type
        define_singleton_method(:execute, &block)
      end

      def to_s
        "<Endpoint[#{endpoint}]>"
      end

      def inspect
        "<Endpoint[#{endpoint}] type=#{type} objectid=#{self.object_id}>"
      end

    end

    include Carnivore::Utils::Params
    include Celluloid::Logger
    include Blockenspiel::DSL

    attr_reader :static, :regex, :only, :except, :endpoint_supervisor

    def initialize(args)
      @only = args[:only]
      @except = args[:except]
      @static = {}
      @regex = {}
      @callback_names = {}
      @endpoint_supervisor = Carnivore::Supervisor.create!.last
      load_endpoints!
    end

    [:get, :put, :post, :delete, :head, :options, :trace].each do |name|
      define_method(name) do |regexp_or_string, args={}, &block|
        endpoint(name, regexp_or_string, args, &block)
      end
    end

    dsl_methods false

    def deliver(msg)
      type = msg[:message][:request].method.to_s.downcase.to_sym
      path = msg[:message][:request].url
      static_points(msg, type, path) || regex_points(msg, type, path)
    end

    def static_points(msg, type, path)
      if(static[type])
        match = static[type].keys.detect do |point|
          !path.scan(/^#{Regexp.escape(point)}\/?(\?|$)/).empty?
        end
        if(match)
          if(static[type][match][:async])
            endpoint_supervisor[callback_name(match, type)].async.execute(msg)
            true
          else
            endpoint_supervisor[callback_name(match, type)].execute(msg)
            true
          end
        end
      end
    end

    def regex_points(msg, type, path)
      if(regex[type])
        match = regex[type].keys.map do |point|
          unless((res = path.scan(/^(#{point})(\?|$)/)).empty?)
            res = res.first
            res.pop # remove empty EOS match
            [point, res]
          end
        end.compact.first
        if(match && !match.empty?)
          if(regex[type][match.first][:async])
            endpoint_supervisor[callback_name(match.first, type)].async.execute(*([msg] + match.last))
            true
          else
            endpoint_supervisor[callback_name(match.first, type)].execute(*([msg] + match.last))
            true
          end
        end
      end
    end

    def callback_name(point, type)
      key = "#{point}_#{type}"
      unless(@callback_names[key])
        @callback_names[key] = Digest::SHA256.hexdigest(key)
      end
      @callback_names[key]
    end

    def endpoint(request_type, regexp_or_string, args, &block)
      request_type = request_type.to_sym
      if(regexp_or_string.is_a?(Regexp))
        regex[request_type] ||= {}
        regex[request_type][regexp_or_string] = args
      else
        static[request_type] ||= {}
        static[request_type][regexp_or_string.sub(%r{/$}, '')] = args
      end
      if(args[:workers] && args[:workers].to_i > 1)
        endpoint_supervisor.pool(Endpoint,
          as: callback_name(regexp_or_string, request_type), size: args[:workers].to_i,
          args: [request_type, regexp_or_string, block]
        )
      else
        endpoint_supervisor.supervise_as(
          callback_name(regexp_or_string, request_type), Endpoint, request_type, regexp_or_string, block
        )
      end
      true
    end

    def endpoints
      [static, regex]
    end

    private

    def load_endpoints!
      self.class.storage.each do |name, block|
        next if only && !only.include?(name.to_s)
        next if except && except.include?(name.to_s)
        Blockenspiel.invoke(block, self)
      end
      true
    end

    class << self
      def define(&block)
        name = File.basename(
          caller.first.match(%r{.*?:}).to_s.sub(':', '')
        ).sub('.rb', '')
        store(name, block)
      end

      def store(name, block)
        storage[name.to_sym] = block
        self
      end

      def storage
        @storage ||= {}
      end
    end
  end
end
